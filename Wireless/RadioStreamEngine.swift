import Foundation
import AudioToolbox

enum RadioSource: String, CaseIterable, Identifiable {
    case mp3 = "MP3"
    case hls = "HLS"
    var id: String { rawValue }
}

struct PlaybackStatus {
    let active: Bool
    let buffering: Bool
    let progress: Double
    let title: String
    let detail: String
    let measuredDelay: Double?
    /// Remaining audio to retain, or a deliberate delay-insertion pause. Nil while connecting.
    var syncBufferRemaining: Double? = nil
}

private struct RadioPacket {
    let number: Int64
    let bytes: Data
    let duration: Double
}

/// Keeps the original MP3 packets until Audio Queue decodes them for the audio output.
/// No lossy re-encoding or time stretching is performed.
// Mutable engine state is confined to work; the status callback is installed before prepare().
final class RadioStreamEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onStatus: ((PlaybackStatus) -> Void)?
    var onPlaybackInterval: ((TimeInterval, Date) -> Void)?

    private let work = DispatchQueue(label: "au.com.kevmarl.Wireless.stream")
    private var streamURL = URL(string: "http://13.54.221.214:8000/sen.mp3")!
    private var hlsURL = URL(string: "https://d2jt3l9ulybyg4.cloudfront.net/chunklist.m3u8?key=monash")!
    private var source: RadioSource = .hls
    private var requestHeaders: [String: String] = [:]
    private var directTypeHint: AudioFileTypeID = kAudioFileMP3Type
    private var generation = 0
    private var streamConnected = false
    private var lastPacketAt = 0.0
    private var retryAttempt = 0
    private var hlsTask: URLSessionDataTask?
    private var hlsNextSequence: Int?
    private var hlsSegments: [(Int, URL)] = []
    private var hlsFetchingSegment = false
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser: AudioFileStreamID?
    private var audioQueue: AudioQueueRef?
    private var audioFormat: AudioStreamBasicDescription?
    private var outputBuffers: [AudioQueueBufferRef] = []
    private var freeBuffers: [AudioQueueBufferRef] = []
    private var queuedBufferDurations: [UInt: TimeInterval] = [:]
    private var packets: [RadioPacket] = []
    private var firstNumber: Int64 = 0
    private var nextNumber: Int64 = 0
    private var playNumber: Int64 = 0
    private var packetDuration = 0.024
    private var latestHLSPacketTime: Double?
    private var queueStartNumber: Int64 = 0
    private var selectedDelay = 0.0
    private var startedAt = 0.0
    private var addedPauseUntil = 0.0
    private var outputStarted = false
    private var outputVolume: Float = 1
    private var wantsPlayback = false
    private var parserReady = false
    private var tick: DispatchSourceTimer?
    private var correction = DelayCorrectionController()
    private var correctionHoldoffUntil = 0.0
    private var lastMeasuredDelay: Double?
    private var correctionNoticeUntil = 0.0
    private var correctionNotice = ""
    private var diagnosticStreamID = "unknown"
    private var diagnosticURL = ""

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var syncEnabled = true
    private var effectiveDelay: Double { syncEnabled ? max(source == .hls ? 2.5 : 0.25, selectedDelay) : 5 }

    func setSyncEnabled(_ enabled: Bool) {
        work.async {
            guard self.syncEnabled != enabled else { return }
            self.syncEnabled = enabled
            self.correction.reset()
            self.lastMeasuredDelay = nil
            self.correctionNoticeUntil = 0
            self.addedPauseUntil = 0
            // Rebuild from the newest retained packets on every mode change.
            // Sync uses the saved TV delay; ordinary live mode waits for the
            // five-second reliability buffer before starting.
            self.disposeOutput()
            if self.wantsPlayback {
                self.tryStartOutput()
            }
            self.publishState()
        }
    }

    func selectSource(_ newSource: RadioSource) {
        work.async {
            guard self.source != newSource else { return }
            self.source = newSource
            self.closeStream()
            self.connect()
        }
    }

    func selectBufferedStream(_ stream: StationStream) {
        work.async {
            self.diagnosticStreamID = stream.id
            self.diagnosticURL = stream.url
            guard let url = stream.playableURL else { return }
            self.closeStream()
            self.requestHeaders = stream.request_headers
            if stream.format == "hls" {
                self.source = .hls
                self.hlsURL = url
                self.directTypeHint = kAudioFileAAC_ADTSType
            } else {
                self.source = .mp3
                self.streamURL = url
                self.directTypeHint = stream.format == "aac" ? kAudioFileAAC_ADTSType : kAudioFileMP3Type
            }
            self.connect()
        }
    }

    func configureSEN(_ station: DirectoryStation, source: RadioSource) {
        work.async {
            let candidates = station.playableStreams
            let stream = candidates.first { $0.id == station.preferred_stream_id && $0.format == source.rawValue.lowercased() }
                ?? candidates.first { $0.format == source.rawValue.lowercased() }
            guard let stream, let url = stream.playableURL else { return }
            self.closeStream()
            self.source = source
            self.requestHeaders = stream.request_headers
            if source == .hls { self.hlsURL = url } else { self.streamURL = url }
            self.connect()
        }
    }

    private func streamRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("0", forHTTPHeaderField: "Icy-MetaData")
        for (name, value) in requestHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    func setDelay(_ seconds: Double) {
        work.async {
            let newValue = min(30, max(0, seconds))
            let oldEffectiveDelay = self.effectiveDelay
            self.selectedDelay = newValue
            guard self.syncEnabled else { return }
            let newEffectiveDelay = self.effectiveDelay
            self.correction.reset()
            self.correctionHoldoffUntil = self.now + 2
            guard self.wantsPlayback else {
                self.publishState()
                return
            }

            if self.outputStarted {
                if newEffectiveDelay < oldEffectiveDelay {
                    self.addedPauseUntil = 0
                    self.repositionOutput()
                } else if newEffectiveDelay > oldEffectiveDelay {
                    if let queue = self.audioQueue { AudioQueuePause(queue) }
                    self.addedPauseUntil = max(self.now, self.addedPauseUntil) + newEffectiveDelay - oldEffectiveDelay
                    self.publishState()
                }
            } else {
                self.publishState()
                self.tryStartOutput()
            }
        }
    }

    func reconnect() {
        work.async {
            guard self.wantsPlayback else { return }
            self.closeStream()
            self.connect()
        }
    }

    func suspendPreparation() {
        work.async {
            guard !self.wantsPlayback else { return }
            self.closeStream()
        }
    }

    func prepare() {
        work.async { self.connect() }
    }

    func start() {
        work.async {
            self.wantsPlayback = true
            if !self.streamConnected { self.connect() }
            self.tryStartOutput()
            self.publishState()
        }
    }

    func setVolume(_ value: Float) {
        work.async {
            self.outputVolume = min(1, max(0, value))
            if let audioQueue = self.audioQueue {
                AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, self.outputVolume)
            }
        }
    }

    private func connect() {
        diagnose("packet.connect", "Connecting retained-buffer backend", metadata: [
            "streamID": diagnosticStreamID,
            "url": diagnosticURL,
            "format": source.rawValue,
            "syncEnabled": "\(syncEnabled)",
            "delaySeconds": String(format: "%.1f", effectiveDelay)
        ])
        guard !streamConnected else { return }
        closeStream()
        streamConnected = true
        startedAt = now
        lastPacketAt = now
        firstNumber = 0
        nextNumber = 0
        playNumber = 0
        packets.removeAll(keepingCapacity: true)
        parserReady = false
        packetDuration = 0.024
        latestHLSPacketTime = nil
        correction.reset()
        lastMeasuredDelay = nil
        correctionNoticeUntil = 0
        publishState()

        let status = AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), streamPropertyCallback, streamPacketsCallback,
                                         source == .mp3 ? directTypeHint : kAudioFileAAC_ADTSType, &parser)
        guard status == noErr else {
            fail("Could not prepare audio playback.")
            return
        }

        startTick()
        if source == .hls {
            refreshHLS()
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 0
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: streamRequest(streamURL))
        task?.resume()
    }

    func stop() {
        work.async {
            self.wantsPlayback = false
            if !self.streamConnected { self.generation += 1 }
            self.disposeOutput()
            self.addedPauseUntil = 0
            self.correction.reset()
            self.lastMeasuredDelay = nil
            self.correctionNoticeUntil = 0
            self.publishState()
        }
    }

    private func closeStream() {
        generation += 1
        streamConnected = false
        hlsTask?.cancel()
        hlsTask = nil
        hlsNextSequence = nil
        hlsSegments.removeAll()
        hlsFetchingSegment = false
        tick?.cancel()
        tick = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        disposeOutput()
        if let parser { AudioFileStreamClose(parser) }
        parser = nil
        audioFormat = nil
        parserReady = false
        addedPauseUntil = 0
    }

    private func disposeOutput() {
        if let audioQueue {
            AudioQueueStop(audioQueue, true)
            AudioQueueDispose(audioQueue, true)
        }
        audioQueue = nil
        outputBuffers.removeAll()
        freeBuffers.removeAll()
        queuedBufferDurations.removeAll()
        outputStarted = false
        lastMeasuredDelay = nil
    }

    private func startTick() {
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = self.now
            if self.wantsPlayback && now - self.lastPacketAt > 12 {
                self.fail("Waiting for reception to return.")
                return
            }
            if self.addedPauseUntil > 0, now >= self.addedPauseUntil {
                self.addedPauseUntil = 0
                if let queue = self.audioQueue { AudioQueueStart(queue, nil) }
            }
            if self.wantsPlayback { self.tryStartOutput() }
            self.checkDelay(at: now)
            self.publishState()
        }
        tick = timer
        timer.resume()
    }

    private func emit(_ status: PlaybackStatus) { onStatus?(status) }

    private func publishState() {
        let now = self.now
        let ready = availableDuration(at: now)
        if !wantsPlayback {
            let full = ready >= effectiveDelay
            emit(PlaybackStatus(active: false, buffering: !full, progress: min(1, ready / effectiveDelay),
                                title: full ? "Ready to play" : "Buffering in background",
                                detail: String(format: "%.1f s of audio ready", ready), measuredDelay: nil))
        } else if addedPauseUntil > now {
            let remaining = addedPauseUntil - now
            emit(PlaybackStatus(active: true, buffering: true, progress: 1 - remaining / max(0.5, selectedDelay),
                                title: String(format: "Adding delay: %.1f s", remaining),
                                detail: "Commentary resumes automatically.", measuredDelay: lastMeasuredDelay,
                                syncBufferRemaining: syncEnabled ? remaining : nil))
        } else if outputStarted {
            let detail = !syncEnabled ? "Live playback · five-second reliability buffer" : now < correctionNoticeUntil
                ? correctionNotice
                : source == .hls && selectedDelay < 2.5
                    ? "HLS needs at least 2.5 s of segment buffer"
                    : String(format: "%.1f s selected delay", selectedDelay)
            emit(PlaybackStatus(active: true, buffering: false, progress: 1,
                                title: "Playing", detail: detail,
                                measuredDelay: lastMeasuredDelay))
        } else {
            let target = effectiveDelay
            let remaining = max(0, target - ready)
            emit(PlaybackStatus(active: true, buffering: true, progress: min(1, ready / target),
                                title: remaining > 0 ? String(format: "Buffering: %.1f s", remaining) : "Starting audio…",
                                detail: syncEnabled ? "Waiting for the selected audio delay." : "Building a short buffer for reliable playback.", measuredDelay: nil,
                                syncBufferRemaining: syncEnabled && streamConnected ? remaining : nil))
        }
    }

    private func availableDuration(at now: Double) -> Double {
        guard streamConnected else { return 0 }
        let elapsed = max(0, now - startedAt)
        let received = Double(packets.count) * packetDuration
        return min(35, elapsed, received)
    }

    private func measuredStreamDelay(at time: Double) -> Double? {
        guard outputStarted, let audioQueue, let audioFormat, audioFormat.mSampleRate > 0 else { return nil }
        var timestamp = AudioTimeStamp()
        var discontinuity = DarwinBoolean(false)
        guard AudioQueueGetCurrentTime(audioQueue, nil, &timestamp, &discontinuity) == noErr,
              !discontinuity.boolValue,
              timestamp.mFlags.contains(.sampleTimeValid) else { return nil }
        let receivedSeconds = Double(nextNumber - queueStartNumber) * packetDuration
            + (source == .hls ? max(0, time - (latestHLSPacketTime ?? time)) : 0)
        return receivedSeconds - timestamp.mSampleTime / audioFormat.mSampleRate
    }

    private func checkDelay(at time: Double) {
        guard syncEnabled, wantsPlayback, outputStarted else { return }
        guard let measured = measuredStreamDelay(at: time) else { return }
        lastMeasuredDelay = max(0, measured)
        // HLS arrives in discrete segments. Its packet cursor already preserves
        // the requested offset from the newest retained audio, while rebuilding
        // Audio Queue in response to segment-edge measurement movement produces
        // audible micro-stutters. Explicit delay changes still reposition HLS.
        guard source != .hls else { return }
        guard addedPauseUntil == 0, time >= correctionHoldoffUntil else { return }
        if correction.observe(measured: measured, target: effectiveDelay, now: time) {
            diagnose("sync.correction", "Correcting accumulated stream lag", metadata: [
                "streamID": diagnosticStreamID,
                "measuredSeconds": String(format: "%.2f", measured),
                "targetSeconds": String(format: "%.2f", effectiveDelay),
                "errorSeconds": String(format: "%.2f", measured - effectiveDelay)
            ])
            correctionNotice = String(format: "Corrected %.1f s of extra lag", measured - effectiveDelay)
            correctionNoticeUntil = time + 4
            repositionOutput()
        }
    }

    private func tryStartOutput() {
        guard wantsPlayback, parserReady, !outputStarted else { return }
        let target = effectiveDelay
        guard availableDuration(at: now) >= target else { return }
        playNumber = max(firstNumber, nextNumber - Int64((target / packetDuration).rounded()))
        queueStartNumber = playNumber
        guard makeOutput() else { return }
        fillAvailableBuffers()
        guard freeBuffers.count < outputBuffers.count, let audioQueue else { return }
        let status = AudioQueueStart(audioQueue, nil)
        if status != noErr { fail("Could not start audio output."); return }
        outputStarted = true
        correction.reset()
        correctionHoldoffUntil = now + 2
        publishState()
    }

    private func repositionOutput() {
        disposeOutput()
        let target = effectiveDelay
        playNumber = max(firstNumber, nextNumber - Int64((target / packetDuration).rounded()))
        queueStartNumber = playNumber
        guard makeOutput() else { return }
        fillAvailableBuffers()
        guard freeBuffers.count < outputBuffers.count, let audioQueue else { return }
        if AudioQueueStart(audioQueue, nil) != noErr { fail("Could not restart audio output."); return }
        outputStarted = true
        correction.reset()
        correctionHoldoffUntil = now + 2
        publishState()
    }

    private func makeOutput() -> Bool {
        guard var format = audioFormat else { return false }
        let result = AudioQueueNewOutput(&format, outputCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &audioQueue)
        guard result == noErr, let audioQueue else {
            fail("Could not create audio output.")
            return false
        }
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, outputVolume)
        for _ in 0..<4 {
            var buffer: AudioQueueBufferRef?
            if AudioQueueAllocateBuffer(audioQueue, 32_768, &buffer) == noErr, let buffer {
                outputBuffers.append(buffer)
                freeBuffers.append(buffer)
            }
        }
        return !freeBuffers.isEmpty
    }

    private func fillAvailableBuffers() {
        guard let audioQueue else { return }
        while let buffer = freeBuffers.last {
            var offset = 0
            var descriptions: [AudioStreamPacketDescription] = []
            var number = playNumber
            while descriptions.count < 10, number < nextNumber {
                let index = Int(number - firstNumber)
                guard packets.indices.contains(index) else { break }
                let data = packets[index].bytes
                guard offset + data.count <= Int(buffer.pointee.mAudioDataBytesCapacity) else { break }
                data.withUnsafeBytes { raw in
                    if let base = raw.baseAddress { memcpy(buffer.pointee.mAudioData.advanced(by: offset), base, data.count) }
                }
                descriptions.append(AudioStreamPacketDescription(mStartOffset: Int64(offset), mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count)))
                offset += data.count
                number += 1
            }
            guard !descriptions.isEmpty else { break }
            buffer.pointee.mAudioDataByteSize = UInt32(offset)
            let result = descriptions.withUnsafeBufferPointer { desc in
                AudioQueueEnqueueBuffer(audioQueue, buffer, UInt32(desc.count), desc.baseAddress)
            }
            guard result == noErr else { fail("Could not queue audio."); return }
            queuedBufferDurations[UInt(bitPattern: buffer)] = Double(descriptions.count) * packetDuration
            freeBuffers.removeLast()
            playNumber = number
        }
    }

    fileprivate func returnedBuffer(_ queue: AudioQueueRef, _ buffer: AudioQueueBufferRef) {
        let returned = ReturnedAudioBuffer(queue: queue, buffer: buffer)
        work.async {
            guard self.wantsPlayback, self.audioQueue == returned.queue else { return }
            if let seconds = self.queuedBufferDurations.removeValue(forKey: UInt(bitPattern: returned.buffer)),
               seconds.isFinite, seconds > 0 {
                self.onPlaybackInterval?(seconds, Date())
            }
            self.freeBuffers.append(returned.buffer)
            self.fillAvailableBuffers()
        }
    }

    fileprivate func receivedProperty(_ id: AudioFileStreamPropertyID) {
        guard id == kAudioFileStreamProperty_ReadyToProducePackets, let parser else { return }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_DataFormat, &size, &format) == noErr else {
            fail("Could not read the stream format.")
            return
        }
        audioFormat = format
        if format.mSampleRate > 0, format.mFramesPerPacket > 0 {
            packetDuration = Double(format.mFramesPerPacket) / format.mSampleRate
        }
        parserReady = true
        diagnose("packet.formatReady", "Compressed audio format parsed", metadata: [
            "streamID": diagnosticStreamID,
            "sampleRate": String(format: "%.0f", format.mSampleRate),
            "packetDurationMs": String(format: "%.1f", packetDuration * 1_000)
        ])
        tryStartOutput()
    }

    fileprivate func receivedPackets(_ count: UInt32, _ input: UnsafeRawPointer, _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard streamConnected else { return }
        guard let descriptions else { return }
        lastPacketAt = now
        retryAttempt = 0
        for index in 0..<Int(count) {
            let desc = descriptions[index]
            let data = Data(bytes: input.advanced(by: Int(desc.mStartOffset)), count: Int(desc.mDataByteSize))
            packets.append(RadioPacket(number: nextNumber, bytes: data, duration: packetDuration))
            nextNumber += 1
        }
        // Keep enough compressed audio history for the maximum delay plus
        // network and output-queue headroom.
        let limit = Int(45 / packetDuration)
        if packets.count > limit {
            let removeCount = packets.count - limit
            packets.removeFirst(removeCount)
            firstNumber += Int64(removeCount)
            playNumber = max(playNumber, firstNumber)
        }
        if wantsPlayback { tryStartOutput() }
        if outputStarted { fillAvailableBuffers() }
    }

    private func fail(_ message: String) {
        closeStream()
        emit(PlaybackStatus(active: wantsPlayback, buffering: true, progress: 0,
                            title: "Reconnecting…", detail: message, measuredDelay: nil))
        let token = generation
        let wait = min(15.0, pow(2.0, Double(min(retryAttempt, 4))))
        diagnose("packet.reconnectScheduled", message, metadata: [
            "streamID": diagnosticStreamID,
            "retry": "\(retryAttempt + 1)",
            "waitSeconds": String(format: "%.1f", wait)
        ])
        retryAttempt += 1
        work.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.generation == token, self.wantsPlayback, !self.streamConnected else { return }
            self.connect()
        }
    }

    private func refreshHLS(depth: Int = 0) {
        guard streamConnected, source == .hls else { return }
        let token = generation
        hlsTask = URLSession.shared.dataTask(with: streamRequest(hlsURL)) { [weak self] data, response, error in
            guard let self else { return }
            self.work.async {
                guard self.generation == token else { return }
                guard error == nil, let data, let text = String(data: data, encoding: .utf8),
                      (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.fail("Could not load the HLS playlist.")
                    return
                }
                let base = response?.url ?? self.hlsURL
                if text.contains("#EXT-X-STREAM-INF:"), depth < 3,
                   let path = text.split(whereSeparator: \.isNewline).first(where: { !$0.hasPrefix("#") }),
                   let variant = URL(string: String(path), relativeTo: base)?.absoluteURL {
                    self.hlsURL = variant
                    self.refreshHLS(depth: depth + 1)
                    return
                }
                guard let playlist = HLSPlaylist.parse(text, relativeTo: base) else {
                    self.fail("Could not load the HLS playlist.")
                    return
                }
                if self.hlsNextSequence == nil { self.hlsNextSequence = playlist.last?.0 }
                if let next = self.hlsNextSequence, let first = playlist.first?.0, next < first {
                    self.fail("The HLS stream moved beyond the buffered audio.")
                    return
                }
                self.hlsSegments = playlist.filter { $0.0 >= (self.hlsNextSequence ?? Int.max) }
                self.fetchNextHLSSegment()
                self.work.asyncAfter(deadline: .now() + 1) { [self] in
                    guard self.generation == token else { return }
                    self.refreshHLS()
                }
            }
        }
        hlsTask?.resume()
    }

    private func fetchNextHLSSegment() {
        guard !hlsFetchingSegment, let next = hlsNextSequence,
              let entry = hlsSegments.first(where: { $0.0 == next }) else { return }
        hlsFetchingSegment = true
        let token = generation
        URLSession.shared.dataTask(with: streamRequest(entry.1)) { [weak self] data, response, error in
            guard let self else { return }
            self.work.async {
                guard self.generation == token else { return }
                self.hlsFetchingSegment = false
                guard error == nil, let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let parser = self.parser else {
                    self.fail("Could not load HLS audio.")
                    return
                }
                let audio = HLSPlaylist.stripLeadingID3(from: data)
                let result = audio.withUnsafeBytes { raw -> OSStatus in
                    guard let base = raw.baseAddress else { return noErr }
                    return AudioFileStreamParseBytes(parser, UInt32(raw.count), base, [])
                }
                guard result == noErr else {
                    self.fail("The HLS audio could not be decoded.")
                    return
                }
                self.latestHLSPacketTime = self.now
                self.hlsNextSequence = next + 1
                self.fetchNextHLSSegment()
            }
        }.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            work.async {
                guard self.session === session else { return }
                self.fail("Stream returned HTTP \(http.statusCode).")
            }
            completionHandler(.cancel)
        } else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        work.async {
            guard self.session === session, let parser = self.parser else { return }
            let result = data.withUnsafeBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return noErr }
                return AudioFileStreamParseBytes(parser, UInt32(raw.count), base, [])
            }
            if result != noErr { self.fail("The MP3 stream could not be decoded.") }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        work.async {
            guard self.session === session else { return }
            self.fail(error == nil ? "The stream ended." : "The stream connection was lost.")
        }
    }
}

private enum HLSPlaylist {
    static func parse(_ text: String, relativeTo base: URL) -> [(Int, URL)]? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "#EXTM3U",
              let sequenceLine = lines.first(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }),
              let first = Int(sequenceLine.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) else { return nil }
        var segments: [(Int, URL)] = []
        for line in lines where !line.hasPrefix("#") && !line.isEmpty {
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { return nil }
            segments.append((first + segments.count, url))
        }
        return segments.isEmpty ? nil : segments
    }

    static func stripLeadingID3(from data: Data) -> Data {
        guard data.count >= 10, data.starts(with: [0x49, 0x44, 0x33]) else { return data }
        let size = data[6..<10].reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
        let offset = 10 + size + ((data[5] & 0x10) != 0 ? 10 : 0)
        return offset < data.count ? data.dropFirst(offset) : Data()
    }
}

private let streamPropertyCallback: AudioFileStream_PropertyListenerProc = { client, _, propertyID, _ in
    Unmanaged<RadioStreamEngine>.fromOpaque(client).takeUnretainedValue().receivedProperty(propertyID)
}

private let streamPacketsCallback: AudioFileStream_PacketsProc = { client, _, packetCount, input, descriptions in
    Unmanaged<RadioStreamEngine>.fromOpaque(client).takeUnretainedValue().receivedPackets(packetCount, input, descriptions)
}

private let outputCallback: AudioQueueOutputCallback = { client, queue, buffer in
    guard let client else { return }
    Unmanaged<RadioStreamEngine>.fromOpaque(client).takeUnretainedValue().returnedBuffer(queue, buffer)
}

// Pointer transport only: dereference on the engine queue after verifying the owning AudioQueue.
private struct ReturnedAudioBuffer: @unchecked Sendable {
    let queue: AudioQueueRef
    let buffer: AudioQueueBufferRef
}

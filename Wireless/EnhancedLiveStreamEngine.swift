import AVFoundation
import AudioToolbox
import Foundation

/// Decodes direct MP3/AAC radio packets to PCM and plays them through the
/// AVAudioEngine Vocal Boost graph. AVPlayer remains the ordinary live backend.
final class EnhancedLiveStreamEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onUnsupportedHLS: (@Sendable (UUID, String) -> Void)?
    var onStatus: (@Sendable (UUID, PlaybackStatus) -> Void)?
    var onPlaybackInterval: (@Sendable (UUID, TimeInterval, Date) -> Void)?

    // Sampling mode reuses the stream parser/decoder without creating or starting
    // an audio engine. Its owner supplies a deadline and stops after one sample.
    private var sampleDiagnostics: ShazamDiagnosticContext?
    private var networkBytes = 0
    private var networkChunks = 0
    private var nextNetworkReport = 0.0
    private var sampleOnly = false
    private var sampledSeconds = 0.0
    private var sampleConsumer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var sampleFailure: (@Sendable () -> Void)?

    func sample(stream: StationStream, diagnostics: ShazamDiagnosticContext? = nil, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                failure: @escaping @Sendable () -> Void) {
        work.async {
            self.close()
            self.sampleDiagnostics = diagnostics
            self.stream = stream; self.sampleOnly = true
            self.sampleConsumer = receive; self.sampleFailure = failure
            self.requested = true; self.connect()
        }
    }

    func observeSamples(_ receive: (@Sendable (AVAudioPCMBuffer) -> Void)?, diagnostics: ShazamDiagnosticContext? = nil) {
        work.async {
            self.sampleConsumer = receive
            self.sampleDiagnostics = diagnostics
            diagnostics?.record("decoder.observer", "Observing existing playback decoder", ["started": String(self.started), "formatReady": String(self.formatReady), "scheduledSeconds": String(self.scheduledSeconds)])
        }
    }

    private let work = DispatchQueue(label: "au.com.kevmarl.Wireless.vocalBoost")
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var playlistURL: URL?
    private var playlistTask: URLSessionDataTask?
    private var segmentTask: URLSessionDataTask?
    private var hlsNextSequence: Int?
    private var hlsSegments: [(sequence: Int, url: URL)] = []
    private var fetchingSegment = false
    private var parser: AudioFileStreamID?
    private var converter: AVAudioConverter?
    private var compressedFormat: AVAudioFormat?
    private var pcmFormat: AVAudioFormat?
    private var processor: VocalBoostProcessor?
    private var stream: StationStream?
    private var level: VocalBoostLevel = .off
    private var musicPreset: MusicPreset = .off
    private var effectName: String { musicPreset != .off ? musicPreset.title : "Vocal Boost" }
    private var effectDescription: String { musicPreset != .off ? musicPreset.title : level == .off ? "Original broadcast audio" : "Vocal Boost · " + level.title }
    private var playbackID = UUID()
    private var pendingFailure = false
    private var generation = 0
    private var requested = false
    private var preparing = false
    private var formatReady = false
    private var started = false
    private var scheduledSeconds = 0.0
    private var outputVolume: Float = 1
    private var packetBacklog: [(Data, AudioStreamPacketDescription)] = []

    func configure(stream: StationStream, level: VocalBoostLevel, musicPreset: MusicPreset = .off, playbackID: UUID) {
        work.async {
            self.close()
            self.sampleOnly = false; self.sampleConsumer = nil; self.sampleFailure = nil; self.sampleDiagnostics = nil
            self.playbackID = playbackID
            self.stream = stream
            self.level = level
            self.musicPreset = musicPreset
        }
    }

    func prepare() {
        work.async {
            self.preparing = true
            self.connect()
        }
    }

    func start() {
        work.async {
            self.requested = true
            self.preparing = false
            if self.session == nil { self.connect() }
            else {
                if self.formatReady {
                    self.receivedProperty(kAudioFileStreamProperty_ReadyToProducePackets)
                    self.decodeBacklog()
                }
            }
        }
    }

    func stop() {
        work.async {
            self.requested = false
            self.close()
            self.sampleConsumer = nil; self.sampleFailure = nil; self.sampleOnly = false; self.sampleDiagnostics = nil
        }
    }

    func setLevel(_ level: VocalBoostLevel, musicPreset: MusicPreset = .off) {
        work.async {
            self.level = level
            self.musicPreset = musicPreset
            do {
                try self.processor?.setLevel(level, musicPreset: musicPreset)
                if self.started, self.requested {
                    self.emit(title: "Playing", detail: self.effectDescription, buffering: false, progress: 1)
                }
            } catch { self.fail("Speech processing could not change level.") }
        }
    }

    func setVolume(_ value: Float) {
        work.async {
            self.outputVolume = min(1, max(0, value))
            self.processor?.setVolume(self.outputVolume)
        }
    }

    private func connect() {
        guard requested || preparing, let stream, let url = stream.playableURL else { return }
        close(keepRequest: true)
        networkBytes = 0; networkChunks = 0; nextNetworkReport = ProcessInfo.processInfo.systemUptime + 2
        sampleDiagnostics?.record("decoder.connect", "Connecting recognition sample decoder", ["streamOrigin": url.host ?? "unknown", "format": stream.format, "sampleOnly": String(sampleOnly), "requestHeaderCount": String(stream.request_headers.count)])
        let hint: AudioFileTypeID = stream.format != "mp3" ? kAudioFileAAC_ADTSType : kAudioFileMP3Type
        let openStatus = AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), enhancedPropertyCallback,
                                  enhancedPacketsCallback, hint, &parser)
        sampleDiagnostics?.record("decoder.parserOpened", "AudioFileStream initialised", ["OSStatus": String(openStatus), "fileTypeHint": String(hint)])
        guard openStatus == noErr else {
            fail("Could not prepare sound processing.")
            return
        }
        if stream.format == "hls" {
            playlistURL = url
            refreshHLS()
            emit(title: "Connecting…", detail: "Preparing HLS \(effectName)", buffering: true, progress: 0)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("0", forHTTPHeaderField: "Icy-MetaData")
        for (name, value) in stream.request_headers { request.setValue(value, forHTTPHeaderField: name) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 0
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
        emit(title: "Connecting…", detail: "Preparing \(effectName)", buffering: true, progress: 0)
    }

    private func close(keepRequest: Bool = false) {
        if sampleConsumer != nil {
            sampleDiagnostics?.record("decoder.stopped", "Sample decoder connection stopped", ["sampledSeconds": String(sampledSeconds), "networkBytes": String(networkBytes), "networkChunks": String(networkChunks), "keepRequest": String(keepRequest)])
        }
        generation += 1
        pendingFailure = false
        playlistTask?.cancel(); playlistTask = nil
        segmentTask?.cancel(); segmentTask = nil
        playlistURL = nil; hlsNextSequence = nil; hlsSegments.removeAll(); fetchingSegment = false
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        if let parser { AudioFileStreamClose(parser) }
        parser = nil
        formatReady = false
        sampledSeconds = 0
        converter = nil
        compressedFormat = nil
        pcmFormat = nil
        processor?.stop(); processor = nil
        packetBacklog.removeAll(keepingCapacity: false)
        started = false
        scheduledSeconds = 0
        if !keepRequest { requested = false; preparing = false }
    }

    fileprivate func receivedProperty(_ property: AudioFileStreamPropertyID) {
        guard !pendingFailure, property == kAudioFileStreamProperty_ReadyToProducePackets else { return }
        formatReady = true
        guard requested, converter == nil, let parser else { return }
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr,
              let source = AVAudioFormat(streamDescription: &description), description.mSampleRate > 0 else {
            fail("Could not read this stream's audio format.")
            return
        }
        let channels = max(1, min(2, AVAudioChannelCount(description.mChannelsPerFrame)))
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: description.mSampleRate,
                                         channels: channels,
                                         interleaved: false),
              let converter = AVAudioConverter(from: source, to: output) else {
            fail("This stream cannot be decoded for sound processing.")
            return
        }
        do {
            let processor = sampleOnly ? nil : try VocalBoostProcessor(format: output, level: level, musicPreset: musicPreset)
            processor?.setVolume(outputVolume)
            sampleDiagnostics?.record("decoder.format", "Decoder PCM format prepared", ShazamDiagnosticContext.audioFormat(output).merging(["compressedFormatID": String(description.mFormatID)]) { _, new in new })
            self.compressedFormat = source
            self.pcmFormat = output
            self.converter = converter
            self.processor = processor
        } catch {
            fail("Sound processing output could not start.")
        }
    }

    fileprivate func receivedPackets(_ count: UInt32, _ input: UnsafeRawPointer,
                                     _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard requested || preparing, !sampleOnly || sampledSeconds < 30, let descriptions else { return }
        for index in 0..<Int(count) {
            var description = descriptions[index]
            let bytes = Data(bytes: input.advanced(by: Int(description.mStartOffset)),
                             count: Int(description.mDataByteSize))
            description.mStartOffset = 0
            packetBacklog.append((bytes, description))
        }
        // Retain a bounded compressed history without activating an audio output.
        if preparing {
            if packetBacklog.count > 256 { packetBacklog.removeFirst(packetBacklog.count - 256) }
        } else { decodeBacklog() }
    }

    private func decodeBacklog() {
        guard !pendingFailure, let converter, let compressedFormat, let pcmFormat,
              !packetBacklog.isEmpty else { return }
        let batch = Array(packetBacklog.prefix(24))
        packetBacklog.removeFirst(batch.count)
        let byteCount = batch.reduce(0) { $0 + $1.0.count }
        let maximum = batch.map { $0.0.count }.max() ?? 1
        let compressed = AVAudioCompressedBuffer(format: compressedFormat,
                                                 packetCapacity: AVAudioPacketCount(batch.count),
                                                 maximumPacketSize: maximum)
        compressed.packetCount = AVAudioPacketCount(batch.count)
        compressed.byteLength = UInt32(byteCount)
        var offset = 0
        for (index, entry) in batch.enumerated() {
            entry.0.copyBytes(to: compressed.data.advanced(by: offset).assumingMemoryBound(to: UInt8.self),
                              count: entry.0.count)
            var description = entry.1
            description.mStartOffset = Int64(offset)
            compressed.packetDescriptions![index] = description
            offset += entry.0.count
        }
        let framesPerPacket = compressedFormat.streamDescription.pointee.mFramesPerPacket
        let frameCapacity = max(4_096, AVAudioFrameCount(batch.count) * max(1, framesPerPacket))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCapacity) else { return }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: pcm, error: &conversionError) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return compressed
        }
        guard conversionError == nil, status != .error, pcm.frameLength > 0 else {
            if let conversionError { sampleDiagnostics?.error("decoder.conversionFailed", "PCM conversion failed", conversionError, details: ["status": String(status.rawValue), "frames": String(pcm.frameLength)]) }
            fail("This stream could not be decoded for sound processing.")
            return
        }
        sampleConsumer?(pcm)
        if sampleOnly {
            sampledSeconds += Double(pcm.frameLength) / pcmFormat.sampleRate
            if sampledSeconds >= 30 {
                // AudioFileStream owns the current callback: close after it returns.
                let token = generation
                work.async { [self] in
                    guard generation == token else { return }
                    close(); sampleConsumer = nil; sampleFailure = nil
                }
            } else if !packetBacklog.isEmpty { decodeBacklog() }
            return
        }
        guard let processor else { return }
        let renderedSeconds = Double(pcm.frameLength) / pcmFormat.sampleRate
        let token = generation
        processor.schedule(pcm) { [weak self] in
            guard let self else { return }
            self.work.async {
                guard self.requested, self.generation == token else { return }
                self.onPlaybackInterval?(self.playbackID, renderedSeconds, Date())
            }
        }
        scheduledSeconds += renderedSeconds
        if !started, scheduledSeconds >= 2 {
            started = true
            do {
                try processor.beginPlayback()
            } catch {
                fail("Sound processing output could not start.")
                return
            }
            emit(title: "Playing", detail: effectDescription, buffering: false, progress: 1)
        } else if !started {
            emit(title: "Buffering…", detail: "Preparing \(effectName)",
                 buffering: true, progress: min(1, scheduledSeconds / 2))
        }
        if !packetBacklog.isEmpty { decodeBacklog() }
    }

    private func fail(_ message: String) {
        guard !pendingFailure else { return }
        sampleDiagnostics?.record("decoder.failed", "Sample parser/decoder failed", ["reason": message, "networkBytes": String(networkBytes), "sampledSeconds": String(sampledSeconds)])
        pendingFailure = true
        let token = generation
        // AudioFileStream invokes parser callbacks synchronously. Never close
        // its parser or destroy its converter before ParseBytes has returned.
        work.async { [self] in
            guard generation == token else { return }
            handleFailure(message)
        }
    }

    private func handleFailure(_ message: String) {
        if sampleOnly {
            let failure = sampleFailure
            close(); sampleConsumer = nil; sampleFailure = nil
            failure?(); return
        }
        if stream?.format == "hls" {
            close()
            onUnsupportedHLS?(playbackID, message)
            return
        }
        let token = generation
        emit(title: "Reconnecting…", detail: message, buffering: true, progress: 0)
        close(keepRequest: true)
        let current = generation
        work.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.requested, self.generation == current, token <= current else { return }
            self.connect()
        }
    }

    private func emit(title: String, detail: String, buffering: Bool, progress: Double) {
        onStatus?(playbackID, PlaybackStatus(active: requested, buffering: buffering, progress: progress,
                                 title: title, detail: detail, measuredDelay: nil))
    }

    private func hlsRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        for (key, value) in stream?.request_headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    /// Adapted from RadioStreamEngine's retained-HLS downloader. Network and
    /// parser work stays on this engine's serial queue, outside the audio thread.
    private func refreshHLS(depth: Int = 0) {
        guard requested || preparing, let url = playlistURL else { return }
        let token = generation
        playlistTask = URLSession.shared.dataTask(with: hlsRequest(url)) { [weak self] data, response, error in
            guard let self else { return }
            self.work.async {
                guard self.generation == token else { return }
                self.logSampleResponse("playlist", response: response, error: error, bytes: data?.count ?? 0)
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, let text = String(data: data, encoding: .utf8) else {
                    self.fail("The HLS playlist could not be loaded for sound processing."); return
                }
                let base = response?.url ?? url
                if let variant = PackedAudioHLS.variant(in: text, base: base), depth < 3 {
                    self.playlistURL = variant; self.refreshHLS(depth: depth + 1); return
                }
                guard let segments = PackedAudioHLS.segments(in: text, base: base) else {
                    self.fail("This HLS container or encryption does not support the sound-processing fallback."); return
                }
                if self.hlsNextSequence == nil { self.hlsNextSequence = segments.last?.sequence }
                if let next = self.hlsNextSequence, let first = segments.first?.sequence, next < first {
                    self.fail("The HLS audio window moved beyond sound processing."); return
                }
                self.hlsSegments = segments.filter { $0.sequence >= (self.hlsNextSequence ?? Int.max) }
                self.fetchHLSSegment()
                self.work.asyncAfter(deadline: .now() + 1) { [self] in
                    guard self.generation == token else { return }
                    self.refreshHLS()
                }
            }
        }
        playlistTask?.resume()
    }

    private func fetchHLSSegment() {
        guard !fetchingSegment, let next = hlsNextSequence,
              let segment = hlsSegments.first(where: { $0.sequence == next }) else { return }
        fetchingSegment = true
        let token = generation
        segmentTask = URLSession.shared.dataTask(with: hlsRequest(segment.url)) { [weak self] data, response, error in
            guard let self else { return }
            self.work.async {
                guard self.generation == token else { return }
                self.fetchingSegment = false
                self.logSampleResponse("segment", response: response, error: error, bytes: data?.count ?? 0)
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, let audio = PackedAudioHLS.audio(in: data), let parser = self.parser else {
                    self.fail("This HLS stream does not supply compatible unencrypted AAC segments."); return
                }
                let result = audio.withUnsafeBytes { bytes -> OSStatus in
                    guard let base = bytes.baseAddress else { return kAudio_ParamError }
                    return AudioFileStreamParseBytes(parser, UInt32(bytes.count), base, [])
                }
                if result != noErr { self.sampleDiagnostics?.record("decoder.parseFailed", "HLS segment parser failed", ["OSStatus": String(result), "sequence": String(next)]) }
                guard result == noErr, !self.pendingFailure, self.generation == token, next < Int.max else {
                    if self.generation == token { self.fail("The HLS audio could not be decoded for sound processing.") }
                    return
                }
                self.hlsNextSequence = next + 1
                self.fetchHLSSegment()
            }
        }
        segmentTask?.resume()
    }

    private func logSampleResponse(_ stage: String, response: URLResponse?, error: Error?, bytes: Int) {
        guard let trace = sampleDiagnostics else { return }
        let details = ["stage": stage, "HTTPStatus": (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "none",
            "MIMEType": response?.mimeType ?? "none", "bytes": String(bytes), "origin": response?.url?.host ?? "none"]
        if let error { trace.error("network.failed", "Sample network request failed", error, details: details) }
        else { trace.record("network.response", "Sample network response", details) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        work.async { [self] in
            if self.session === session { logSampleResponse("response-headers", response: response, error: nil, bytes: 0) }
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        work.async {
            guard !self.pendingFailure, self.session === session, let parser = self.parser else { return }
            self.networkBytes += data.count; self.networkChunks += 1
            if ProcessInfo.processInfo.systemUptime >= self.nextNetworkReport {
                self.nextNetworkReport = ProcessInfo.processInfo.systemUptime + 2
                self.sampleDiagnostics?.record("network.progress", "Sample connection received data", ["bytes": String(self.networkBytes), "chunks": String(self.networkChunks)])
            }
            let result = data.withUnsafeBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return noErr }
                return AudioFileStreamParseBytes(parser, UInt32(bytes.count), base, [])
            }
            if result != noErr {
                self.sampleDiagnostics?.record("decoder.parseFailed", "AudioFileStream rejected network bytes", ["OSStatus": String(result)])
                self.fail("The direct stream could not be decoded.")
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        work.async {
            guard self.session === session else { return }
            self.logSampleResponse("connection-completed", response: task.response, error: error, bytes: self.networkBytes)
            if !self.requested { self.close(); return }
            self.fail(error == nil ? "The stream ended." : "The stream connection was lost.")
        }
    }
}

private let enhancedPropertyCallback: AudioFileStream_PropertyListenerProc = { client, _, property, _ in
    Unmanaged<EnhancedLiveStreamEngine>.fromOpaque(client).takeUnretainedValue().receivedProperty(property)
}

private let enhancedPacketsCallback: AudioFileStream_PacketsProc = { client, _, count, input, descriptions in
    Unmanaged<EnhancedLiveStreamEngine>.fromOpaque(client).takeUnretainedValue()
        .receivedPackets(count, input, descriptions)
}

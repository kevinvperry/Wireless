import AVFoundation
import AudioToolbox
import Foundation

/// Decodes direct MP3/AAC radio packets to PCM and plays them through the
/// AVAudioEngine Vocal Boost graph. AVPlayer remains the ordinary live backend.
final class EnhancedLiveStreamEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onUnsupportedHLS: (@Sendable (UUID, String) -> Void)?
    var onStatus: (@Sendable (UUID, PlaybackStatus) -> Void)?
    var onPlaybackInterval: (@Sendable (UUID, TimeInterval, Date) -> Void)?

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
    private var bassBoost: BassBoostLevel = .off
    private var effectName: String { bassBoost != .off ? bassBoost.title : "Vocal Boost" }
    private var effectDescription: String { bassBoost != .off ? bassBoost.title : level == .off ? "Original broadcast audio" : "Vocal Boost · " + level.title }
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

    func configure(stream: StationStream, level: VocalBoostLevel, bassBoost: BassBoostLevel = .off, playbackID: UUID) {
        work.async {
            self.close()
            self.playbackID = playbackID
            self.stream = stream
            self.level = level
            self.bassBoost = bassBoost
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
        }
    }

    func setLevel(_ level: VocalBoostLevel, bassBoost: BassBoostLevel = .off) {
        work.async {
            self.level = level
            self.bassBoost = bassBoost
            do {
                try self.processor?.setLevel(level, bassBoost: bassBoost)
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
        let hint: AudioFileTypeID = stream.format != "mp3" ? kAudioFileAAC_ADTSType : kAudioFileMP3Type
        guard AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), enhancedPropertyCallback,
                                  enhancedPacketsCallback, hint, &parser) == noErr else {
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
        guard requested, processor == nil, let parser else { return }
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
            let processor = try VocalBoostProcessor(format: output, level: level, bassBoost: bassBoost)
            processor.setVolume(outputVolume)
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
        guard requested || preparing, let descriptions else { return }
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
        guard !pendingFailure, let converter, let compressedFormat, let pcmFormat, let processor,
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
            fail("This stream could not be decoded for sound processing.")
            return
        }
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
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, let audio = PackedAudioHLS.audio(in: data), let parser = self.parser else {
                    self.fail("This HLS stream does not supply compatible unencrypted AAC segments."); return
                }
                let result = audio.withUnsafeBytes { bytes -> OSStatus in
                    guard let base = bytes.baseAddress else { return kAudio_ParamError }
                    return AudioFileStreamParseBytes(parser, UInt32(bytes.count), base, [])
                }
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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        work.async {
            guard !self.pendingFailure, self.session === session, let parser = self.parser else { return }
            let result = data.withUnsafeBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return noErr }
                return AudioFileStreamParseBytes(parser, UInt32(bytes.count), base, [])
            }
            if result != noErr { self.fail("The direct stream could not be decoded.") }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        work.async {
            guard self.session === session else { return }
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

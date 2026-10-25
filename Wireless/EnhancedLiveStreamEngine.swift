import AVFoundation
import AudioToolbox
import Foundation

/// Decodes direct MP3/AAC radio packets to PCM and plays them through the
/// AVAudioEngine Vocal Boost graph. AVPlayer remains the ordinary live backend.
final class EnhancedLiveStreamEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onStatus: (@Sendable (PlaybackStatus) -> Void)?
    var onPlaybackInterval: (@Sendable (TimeInterval, Date) -> Void)?

    private let work = DispatchQueue(label: "au.com.kevmarl.Wireless.vocalBoost")
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser: AudioFileStreamID?
    private var converter: AVAudioConverter?
    private var compressedFormat: AVAudioFormat?
    private var pcmFormat: AVAudioFormat?
    private var processor: VocalBoostProcessor?
    private var stream: StationStream?
    private var level: VocalBoostLevel = .off
    private var generation = 0
    private var requested = false
    private var preparing = false
    private var formatReady = false
    private var started = false
    private var scheduledSeconds = 0.0
    private var outputVolume: Float = 1
    private var packetBacklog: [(Data, AudioStreamPacketDescription)] = []

    func configure(stream: StationStream, level: VocalBoostLevel) {
        work.async {
            self.close()
            self.stream = stream
            self.level = level
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

    func setVolume(_ value: Float) {
        work.async {
            self.outputVolume = min(1, max(0, value))
            self.processor?.setVolume(self.outputVolume)
        }
    }

    private func connect() {
        guard requested || preparing, let stream, let url = stream.playableURL else { return }
        close(keepRequest: true)
        let hint: AudioFileTypeID = stream.format == "aac" ? kAudioFileAAC_ADTSType : kAudioFileMP3Type
        guard AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), enhancedPropertyCallback,
                                  enhancedPacketsCallback, hint, &parser) == noErr else {
            fail("Could not prepare Vocal Boost playback.")
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
        emit(title: "Connecting…", detail: "Preparing Vocal Boost", buffering: true, progress: 0)
    }

    private func close(keepRequest: Bool = false) {
        generation += 1
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
        guard property == kAudioFileStreamProperty_ReadyToProducePackets else { return }
        formatReady = true
        guard requested, let parser else { return }
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
            fail("This stream cannot be decoded for Vocal Boost.")
            return
        }
        do {
            let processor = try VocalBoostProcessor(format: output, level: level)
            processor.setVolume(outputVolume)
            self.compressedFormat = source
            self.pcmFormat = output
            self.converter = converter
            self.processor = processor
        } catch {
            fail("Vocal Boost audio output could not start.")
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
        guard let converter, let compressedFormat, let pcmFormat, let processor,
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
            fail("This stream could not be decoded for Vocal Boost.")
            return
        }
        let renderedSeconds = Double(pcm.frameLength) / pcmFormat.sampleRate
        let token = generation
        processor.schedule(pcm) { [weak self] in
            guard let self else { return }
            self.work.async {
                guard self.requested, self.generation == token else { return }
                self.onPlaybackInterval?(renderedSeconds, Date())
            }
        }
        scheduledSeconds += renderedSeconds
        if !started, scheduledSeconds >= 2 {
            started = true
            do {
                try processor.beginPlayback()
            } catch {
                fail("Vocal Boost audio output could not start.")
                return
            }
            emit(title: "Playing", detail: "Vocal Boost · " + level.title, buffering: false, progress: 1)
        } else if !started {
            emit(title: "Buffering…", detail: "Preparing Vocal Boost",
                 buffering: true, progress: min(1, scheduledSeconds / 2))
        }
        if !packetBacklog.isEmpty { decodeBacklog() }
    }

    private func fail(_ message: String) {
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
        onStatus?(PlaybackStatus(active: requested, buffering: buffering, progress: progress,
                                 title: title, detail: detail, measuredDelay: nil))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        work.async {
            guard self.session === session, let parser = self.parser else { return }
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

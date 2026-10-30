import AVFoundation

/// Reads the selected AVPlayer item's PCM, paced to its playback clock. Never
/// pulls an entire segment ahead of the sound the listener is hearing.
@available(iOS 27.0, *)
@MainActor final class HLSSongSample {
    private let diagnostics: ShazamDiagnosticContext
    private var polls = 0
    private var deliveredFrames = 0
    private var emptyPolls = 0
    private var staleBuffers = 0
    private var futureWaits = 0
    private var nextHeartbeat = ProcessInfo.processInfo.systemUptime + 2
    private let item: AVPlayerItem
    private let output: AVPlayerItemSampleBufferOutput
    private var timer: Timer?
    private var pending: AVPlayerItemSampleBufferOutput.SampleBufferInSequence?
    private var lastEnd: Double?
    private var loggedFirstSample = false
    private let receive: (AVAudioPCMBuffer) -> Void
    private let failure: () -> Void

    init(item: AVPlayerItem, receive: @escaping (AVAudioPCMBuffer) -> Void,
         diagnostics: ShazamDiagnosticContext = ShazamDiagnosticContext(), failure: @escaping () -> Void) {
        self.diagnostics = diagnostics
        self.item = item; self.receive = receive; self.failure = failure
        let configuration = AVPlayerItemSampleBufferOutputAudioConfiguration()
        configuration.requestedAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!.formatDescription
        output = AVPlayerItemSampleBufferOutput(configuration: configuration)
        output.suppressesPlayerRendering = false
        item.add(output)
        diagnostics.record("hls.attached", "HLS PCM output attached", ["requestedRate": "44100", "requestedChannels": "1", "suppressesRendering": String(output.suppressesPlayerRendering)])
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
    }
    func stop() {
        guard timer != nil else { return }
        diagnostics.record("hls.detached", "HLS PCM output detached", snapshot())
        timer?.invalidate(); timer = nil; pending = nil
        item.remove(output)
    }
    private func snapshot() -> [String: String] {
        var details = ["polls": String(polls), "emptyPolls": String(emptyPolls), "deliveredFrames": String(deliveredFrames),
            "staleBuffersSkipped": String(staleBuffers), "futureBufferWaits": String(futureWaits),
            "itemStatus": String(item.status.rawValue), "playbackPosition": String(item.currentTime().seconds)]
        if let error = item.error { details.merge(ShazamDiagnosticContext.errorFields(error)) { _, new in new } }
        if let event = item.errorLog()?.events.last {
            details["playerErrorStatusCode"] = String(event.errorStatusCode)
            details["playerErrorDomain"] = event.errorDomain
            details["playerErrorComment"] = event.errorComment ?? "none"
        }
        if let event = item.accessLog()?.events.last {
            details["playerStalls"] = String(event.numberOfStalls)
            details["observedBitrate"] = String(event.observedBitrate)
            details["indicatedBitrate"] = String(event.indicatedBitrate)
            details["mediaRequests"] = String(event.numberOfMediaRequests)
        }
        return details
    }
    private func read() {
        guard timer != nil else { return }
        polls += 1
        if diagnostics.enabled, ProcessInfo.processInfo.systemUptime >= nextHeartbeat {
            nextHeartbeat = ProcessInfo.processInfo.systemUptime + 2
            diagnostics.record("hls.heartbeat", "HLS PCM output health", snapshot())
        }
        // Cap work per tick, even if the output supplies a large buffered history.
        for _ in 0..<12 {
            if pending == nil { pending = output.nextAvailableSampleBuffer() }
            guard let next = pending else { emptyPolls += 1; return }
            var future = false
            var failed = false
            var failureReason = "unknown"
            next.sampleBuffer.withUnsafeSampleBuffer { sample in
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0 else { return }
                let position = CMSampleBufferGetOutputPresentationTimeStamp(sample).seconds
                let current = item.currentTime().seconds
                if !loggedFirstSample {
                    loggedFirstSample = true
                    diagnostics.record("hls.firstBuffer", "HLS PCM output received", [
                        "samplePosition": String(position), "playbackPosition": String(current), "frames": String(frames)
                    ])
                }
                guard position.isFinite, current.isFinite else { failed = true; failureReason = "non-finite-timestamp"; return }
                if position > current + 0.1 { futureWaits += 1; future = true; return }
                // Ignore pre-existing decoder history when attaching mid-stream.
                if position < current - 1 { staleBuffers += 1; return }
                if next.sequenceWasRestarted, lastEnd != nil { failed = true; failureReason = "sequence-restarted"; return }
                if let lastEnd, abs(position - lastEnd) > 0.25 { failed = true; failureReason = "audio-discontinuity-\(position - lastEnd)-seconds"; return }
                guard let description = CMSampleBufferGetFormatDescription(sample) else { failed = true; failureReason = "missing-format-description"; return }
                let format = AVAudioFormat(cmAudioFormatDescription: description)
                guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
                    failed = true; failureReason = "PCM-allocation-failed"; return
                }
                if deliveredFrames == 0 { diagnostics.record("hls.format", "Actual HLS PCM format", ShazamDiagnosticContext.audioFormat(format)) }
                pcm.frameLength = AVAudioFrameCount(frames)
                let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
                guard status == noErr else { failed = true; failureReason = "PCM-copy-OSStatus-\(status)"; return }
                deliveredFrames += frames
                lastEnd = position + Double(frames) / format.sampleRate
                receive(pcm)
            }
            if future { return }
            pending = nil
            if failed {
                diagnostics.record("hls.failed", "HLS capture rejected audio", snapshot().merging(["reason": failureReason]) { _, new in new })
                stop(); failure(); return
            }
        }
    }
}

import AVFoundation

/// Reads the selected AVPlayer item's PCM, paced to its playback clock. Never
/// pulls an entire segment ahead of the sound the listener is hearing.
@available(iOS 27.0, *)
@MainActor final class HLSSongSample {
    private let item: AVPlayerItem
    private let output: AVPlayerItemSampleBufferOutput
    private var timer: Timer?
    private var pending: AVPlayerItemSampleBufferOutput.SampleBufferInSequence?
    private var lastEnd: Double?
    private var loggedFirstSample = false
    private let receive: (AVAudioPCMBuffer) -> Void
    private let failure: () -> Void

    init(item: AVPlayerItem, receive: @escaping (AVAudioPCMBuffer) -> Void,
         failure: @escaping () -> Void) {
        self.item = item; self.receive = receive; self.failure = failure
        let configuration = AVPlayerItemSampleBufferOutputAudioConfiguration()
        configuration.requestedAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!.formatDescription
        output = AVPlayerItemSampleBufferOutput(configuration: configuration)
        output.suppressesPlayerRendering = false
        item.add(output)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
    }
    func stop() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil; pending = nil
        item.remove(output)
    }
    private func read() {
        // Cap work per tick, even if the output supplies a large buffered history.
        for _ in 0..<12 {
            if pending == nil { pending = output.nextAvailableSampleBuffer() }
            guard let next = pending else { return }
            var future = false
            var failed = false
            next.sampleBuffer.withUnsafeSampleBuffer { sample in
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0 else { return }
                let position = CMSampleBufferGetOutputPresentationTimeStamp(sample).seconds
                let current = item.currentTime().seconds
                if !loggedFirstSample {
                    loggedFirstSample = true
                    StreamDiagnosticLogger.shared.record("recognition.hlsAudio", "HLS PCM output received", metadata: [
                        "samplePosition": String(position), "playbackPosition": String(current), "frames": String(frames)
                    ])
                }
                guard position.isFinite, current.isFinite else { failed = true; return }
                if position > current + 0.1 { future = true; return }
                // Ignore pre-existing decoder history when attaching mid-stream.
                if position < current - 1 { return }
                if next.sequenceWasRestarted, lastEnd != nil { failed = true; return }
                if let lastEnd, abs(position - lastEnd) > 0.25 { failed = true; return }
                guard let description = CMSampleBufferGetFormatDescription(sample) else { failed = true; return }
                let format = AVAudioFormat(cmAudioFormatDescription: description)
                guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
                    failed = true; return
                }
                pcm.frameLength = AVAudioFrameCount(frames)
                guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                    into: pcm.mutableAudioBufferList) == noErr else { failed = true; return }
                lastEnd = position + Double(frames) / format.sampleRate
                receive(pcm)
            }
            if future { return }
            pending = nil
            if failed { stop(); failure(); return }
        }
    }
}

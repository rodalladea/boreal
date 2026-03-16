import AVFoundation
import Combine

class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    @Published var level: Float = 0.0

    private var audioEngine: AVAudioEngine?

    private init() {}

    func start() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20 * log10(max(rms, 1e-7))
            let normalized = Float(max(0, min(1, (db + 60) / 60)))

            DispatchQueue.main.async { [weak self] in
                self?.level = normalized
            }
        }

        do {
            try engine.start()
            audioEngine = engine
        } catch {
            print("AudioLevelMonitor: failed to start - \(error)")
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        DispatchQueue.main.async {
            self.level = 0
        }
    }

    deinit {
        stop()
    }
}

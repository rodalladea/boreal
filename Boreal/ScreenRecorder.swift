import ScreenCaptureKit
import AVFoundation
import AppKit
import Combine

enum RecordingQuality: String, CaseIterable {
    case low
    case medium
    case high

    var minFrameInterval: CMTime {
        switch self {
        case .low:    return CMTime(value: 1, timescale: 15)
        case .medium: return CMTime(value: 1, timescale: 30)
        case .high:   return CMTime(value: 1, timescale: 60)
        }
    }

    var localizedName: String {
        switch self {
        case .low:    return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high:   return String(localized: "High")
        }
    }
}

class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published var isRecording = false
    @Published var quality: RecordingQuality = .medium
    @Published var recordingDuration: TimeInterval = 0

    /// ID da janela de controles — preenchido pelo AppDelegate após criar a janela
    var controlsWindowID: CGWindowID = 0

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var pendingOutputURL: URL?
    private var recordingTimer: Timer?

    func startRecording() {
        guard !isRecording else { return }
        Task { await _startRecording() }
    }

    private func _startRecording() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                print("[Boreal] No display found")
                return
            }

            // Exclui a janela de controles da captura
            let excludedWindows = content.windows.filter { $0.windowID == controlsWindowID }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            let streamConfig = SCStreamConfiguration()
            streamConfig.width = display.width
            streamConfig.height = display.height
            streamConfig.minimumFrameInterval = quality.minFrameInterval
            streamConfig.showsCursor = true

            let url = makeOutputURL()
            pendingOutputURL = url

            let outputConfig = SCRecordingOutputConfiguration()
            outputConfig.outputURL = url
            outputConfig.outputFileType = .mov

            let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
            let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output

            await MainActor.run {
                self.isRecording = true
                self.recordingDuration = 0
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    self?.recordingDuration += 1
                }
            }
        } catch {
            print("[Boreal] Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        Task {
            try? await stream?.stopCapture()
        }
    }

    private func makeOutputURL() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let folder = movies.appendingPathComponent("Boreal", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("[Boreal] Failed to create output folder: \(error)")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return folder.appendingPathComponent("Boreal \(formatter.string(from: Date())).mov")
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        stream = nil
        recordingOutput = nil

        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingDuration = 0
            self.isRecording = false

            if let url = self.pendingOutputURL {
                print("[Boreal] Saved to \(url.path)")
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
            self.pendingOutputURL = nil
        }
    }

    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: any Error) {
        stream = nil
        recordingOutput = nil

        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingDuration = 0
            self.isRecording = false
            self.pendingOutputURL = nil
            print("[Boreal] Recording error: \(error.localizedDescription)")
        }
    }
}

import ScreenCaptureKit
import AVFoundation
import AppKit
import Combine

enum RecordingResolution: String, CaseIterable {
    case native = "native"
    case p1440  = "1440p"
    case p1080  = "1080p"
    case p720   = "720p"

    func dimensions(for display: SCDisplay) -> (width: Int, height: Int) {
        let scaleFactor: Int
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            scaleFactor = mode.pixelWidth / mode.width
        } else {
            scaleFactor = 1
        }

        let ratio = Double(display.width) / Double(display.height)

        switch self {
        case .native:
            return (display.width * scaleFactor, display.height * scaleFactor)
        case .p1440:
            return (Int(1440.0 * ratio), 1440)
        case .p1080:
            return (Int(1080.0 * ratio), 1080)
        case .p720:
            return (Int(720.0 * ratio), 720)
        }
    }

    var localizedName: String {
        switch self {
        case .native: return String(localized: "Native")
        case .p1440:  return "1440p"
        case .p1080:  return "1080p"
        case .p720:   return "720p"
        }
    }
}

enum RecordingFPS: Int, CaseIterable {
    case fps60 = 60
    case fps30 = 30
    case fps24 = 24
    case fps15 = 15

    var frameInterval: CMTime { CMTime(value: 1, timescale: CMTimeScale(rawValue)) }
    var localizedName: String { "\(rawValue) fps" }
}

class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published var isRecording = false
    @Published var resolution: RecordingResolution = .native
    @Published var fps: RecordingFPS = .fps30
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

            let dims = resolution.dimensions(for: display)
            let streamConfig = SCStreamConfiguration()
            streamConfig.width = dims.width
            streamConfig.height = dims.height
            streamConfig.minimumFrameInterval = fps.frameInterval
            streamConfig.captureResolution = .best
            streamConfig.showsCursor = true

            let url = makeOutputURL()
            pendingOutputURL = url

            let outputConfig = SCRecordingOutputConfiguration()
            outputConfig.outputURL = url
            outputConfig.outputFileType = .mov
            outputConfig.videoCodecType = .hevc

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

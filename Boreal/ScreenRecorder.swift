import AVFoundation
import Combine
import AppKit

enum RecordingQuality: String, CaseIterable {
    case low
    case medium
    case high

    /// Frame interval passed to AVCaptureScreenInput.minFrameDuration.
    /// Lower fps = smaller file size (lower quality).
    var frameInterval: CMTime {
        switch self {
        case .low:    return CMTime(value: 1, timescale: 15)   // 15 fps
        case .medium: return CMTime(value: 1, timescale: 30)   // 30 fps
        case .high:   return CMTime(value: 1, timescale: 60)   // 60 fps
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

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?

    func startRecording() {
        guard !isRecording else { return }

        guard let screen = NSScreen.main,
              let displayIDRaw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")],
              let displayID = displayIDRaw as? CGDirectDisplayID
        else {
            print("[Boreal] Could not get display ID")
            return
        }

        guard let screenInput = AVCaptureScreenInput(displayID: displayID) else {
            print("[Boreal] Could not create AVCaptureScreenInput — screen recording permission may be denied")
            return
        }

        screenInput.minFrameDuration = quality.frameInterval
        screenInput.capturesCursor = true

        let session = AVCaptureSession()
        let output = AVCaptureMovieFileOutput()

        guard session.canAddInput(screenInput) else {
            print("[Boreal] Cannot add screen input to session")
            return
        }
        guard session.canAddOutput(output) else {
            print("[Boreal] Cannot add movie output to session")
            return
        }

        session.addInput(screenInput)
        session.addOutput(output)
        session.startRunning()

        self.captureSession = session
        self.movieOutput = output

        let outputURL = makeOutputURL()
        output.startRecording(to: outputURL, recordingDelegate: self)

        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput?.stopRecording()
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

extension ScreenRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        captureSession?.stopRunning()
        captureSession = nil
        movieOutput = nil

        DispatchQueue.main.async {
            self.isRecording = false
            if let error {
                print("[Boreal] Recording error: \(error.localizedDescription)")
            } else {
                print("[Boreal] Saved to \(outputFileURL.path)")
                NSWorkspace.shared.open(outputFileURL.deletingLastPathComponent())
            }
        }
    }
}

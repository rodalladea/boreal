import AVFoundation
import AppKit
import SwiftUI

struct CameraView: View {
    @ObservedObject private var camera = CameraManager.shared

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)

            if !camera.isAuthorized && !camera.isSettingUpCamera {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)

                    Text("Camera permission required")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("Please allow camera access in settings")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if camera.isSettingUpCamera {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding()

                    Text("Initializing camera...")
                        .font(.body)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if !camera.cameraAvailable {
                VStack(spacing: 20) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)

                    Text("Camera not available")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("Check if your Mac has a connected camera")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .onDisappear {
            camera.stopSession()
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if nsView.session !== session {
            nsView.session = session
        }
    }
}

class CameraPreviewNSView: NSView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.previewLayer.session = session
                self.needsLayout = true
                self.needsDisplay = true
            }
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPreviewLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreviewLayer()
    }

    private func setupPreviewLayer() {
        wantsLayer = true
        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()

        if previewLayer.superlayer == nil, let layer = self.layer {
            layer.addSublayer(previewLayer)
        }

        previewLayer.frame = bounds
    }

    override var wantsUpdateLayer: Bool {
        return true
    }
}

class CameraManager: ObservableObject {
    static let shared = CameraManager()

    @Published var isAuthorized = false
    @Published var cameraAvailable = false
    @Published var isSettingUpCamera = true
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var currentCamera: AVCaptureDevice?

    let session = AVCaptureSession()

    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var wasRunningBeforeInterruption = false

    init() {
        setupNotifications()
        checkAuthorization()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesDidChange),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesDidChange),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        wasRunningBeforeInterruption = session.isRunning
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        if wasRunningBeforeInterruption {
            sessionQueue.async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("Camera session error: \(error.localizedDescription)")
        }
        restartSession()
    }

    @objc private func devicesDidChange(_ notification: Notification) {
        refreshAvailableCameras()
    }

    private func refreshAvailableCameras() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .external,
            ]

            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )

            let cameras = discoverySession.devices

            Task { @MainActor in
                self.availableCameras = cameras
            }

            let currentId = self.currentInput?.device.uniqueID
            let currentStillExists = cameras.contains { $0.uniqueID == currentId }

            if !currentStillExists {
                if let fallback = cameras.first {
                    self.session.beginConfiguration()
                    self.configureCamera(fallback)
                } else {
                    Task { @MainActor in
                        self.currentCamera = nil
                        self.cameraAvailable = false
                    }
                }
            }
        }
    }

    private func restartSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard !self.session.isRunning else { return }

            let camera = self.currentInput?.device

            if let camera = camera {
                self.session.beginConfiguration()
                self.configureCamera(camera)
            } else {
                self.session.startRunning()
            }

            if !self.session.isRunning {
                self.sessionQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.session.startRunning()
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func checkAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            Task { @MainActor in
                isAuthorized = true
            }
            setupCamera()
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            Task { @MainActor in
                isAuthorized = false
                isSettingUpCamera = false
            }
        @unknown default:
            Task { @MainActor in
                isAuthorized = false
                isSettingUpCamera = false
            }
        }
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }

            Task { @MainActor in
                self.isAuthorized = granted
            }

            if granted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.setupCamera()
                }
            } else {
                Task { @MainActor in
                    self.isSettingUpCamera = false
                }
            }
        }
    }

    private func setupCamera() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)

        guard authStatus == .authorized else {
            Task { @MainActor in
                self.isAuthorized = false
                self.isSettingUpCamera = false
            }
            return
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            Task { @MainActor in
                self.isSettingUpCamera = true
            }

            self.session.beginConfiguration()

            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .external,
            ]

            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )

            let cameras = discoverySession.devices

            Task { @MainActor in
                self.availableCameras = cameras
            }

            var selectedCamera: AVCaptureDevice?

            selectedCamera = cameras.first {
                $0.position == .front && $0.deviceType == .builtInWideAngleCamera
            }

            if selectedCamera == nil {
                selectedCamera = cameras.first { $0.position == .front }
            }

            if selectedCamera == nil {
                selectedCamera = cameras.first {
                    $0.position == .back && $0.deviceType == .builtInWideAngleCamera
                }
            }

            if selectedCamera == nil {
                selectedCamera = cameras.first { $0.position == .back }
            }

            if selectedCamera == nil {
                selectedCamera = cameras.first
            }

            guard let camera = selectedCamera else {
                Task { @MainActor in
                    self.cameraAvailable = false
                    self.isSettingUpCamera = false
                }
                self.session.commitConfiguration()
                return
            }

            self.configureCamera(camera)
        }
    }

    private func configureCamera(_ camera: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: camera)

            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
                self.session.commitConfiguration()

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                Task { @MainActor in
                    self.currentCamera = camera
                    self.cameraAvailable = true
                    self.isSettingUpCamera = false
                }
            } else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.cameraAvailable = false
                    self.isSettingUpCamera = false
                }
            }

        } catch {
            print("Camera error: \(error.localizedDescription)")
            self.session.commitConfiguration()
            Task { @MainActor in
                self.cameraAvailable = false
                self.isSettingUpCamera = false
            }
        }
    }

    func switchCamera(to camera: AVCaptureDevice) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.configureCamera(camera)
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

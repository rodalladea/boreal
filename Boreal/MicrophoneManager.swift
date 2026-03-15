import AVFoundation
import Combine

class MicrophoneManager: ObservableObject {
    static let shared = MicrophoneManager()

    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var currentMicrophone: AVCaptureDevice?

    private init() {
        refreshDevices()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    @objc private func devicesChanged() {
        refreshDevices()
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices

        DispatchQueue.main.async {
            self.availableMicrophones = devices

            if let current = self.currentMicrophone,
               !devices.contains(where: { $0.uniqueID == current.uniqueID }) {
                self.currentMicrophone = devices.first
            } else if self.currentMicrophone == nil {
                self.currentMicrophone = devices.first
            }
        }
    }

    func switchMicrophone(to device: AVCaptureDevice) {
        DispatchQueue.main.async {
            self.currentMicrophone = device
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

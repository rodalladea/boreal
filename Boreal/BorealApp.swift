import SwiftUI
import AppKit
import AVFoundation

@main
struct BorealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var cameraManager = CameraManager.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) {}

            CommandMenu("Camera") {
                ForEach(Array(cameraManager.availableCameras.enumerated()), id: \.element.uniqueID) { index, camera in
                    CameraMenuItem(
                        camera: camera,
                        isSelected: cameraManager.currentCamera?.uniqueID == camera.uniqueID,
                        index: index
                    ) {
                        cameraManager.switchCamera(to: camera)
                    }
                }

                if cameraManager.availableCameras.isEmpty {
                    Text("No cameras available")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CameraMenuItem: View {
    let camera: AVCaptureDevice
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark")
                }
                Text(camera.localizedName)
            }
        }
        .modifier(CameraShortcutModifier(index: index))
    }
}

struct CameraShortcutModifier: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        } else {
            content
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.windows.first?.close()
            self.createOverlayWindow()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        repositionWindow()
    }

    private func repositionWindow() {
        guard let panel = overlayWindow, let screen = NSScreen.main else { return }

        let windowSize = panel.frame.size
        let padding: CGFloat = 20

        let xPos = screen.visibleFrame.maxX - windowSize.width - padding
        let yPos = screen.visibleFrame.maxY - windowSize.height - padding

        panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }

    func createOverlayWindow() {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 320, height: 240)
        let padding: CGFloat = 20

        let xPos = screen.visibleFrame.maxX - windowSize.width - padding
        let yPos = screen.visibleFrame.maxY - windowSize.height - padding

        let frame = NSRect(x: xPos, y: yPos, width: windowSize.width, height: windowSize.height)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.overlayWindow = panel
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

import SwiftUI
import AppKit
import AVFoundation
import Combine

@main
struct BorealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()

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

        setupGlobalShortcuts()

        CameraManager.shared.$availableCameras
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraMenu() }
            .store(in: &cancellables)

        CameraManager.shared.$currentCamera
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraMenu() }
            .store(in: &cancellables)
    }

    // MARK: - Menu Bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = buildAppMenu()
        mainMenu.addItem(appMenuItem)

        let cameraMenuItem = NSMenuItem()
        cameraMenuItem.submenu = buildCameraMenu()
        mainMenu.addItem(cameraMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: String(localized: "About Boreal"),
            action: #selector(showAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: String(localized: "Hide Boreal"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(showAllItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Boreal"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    private func buildCameraMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Camera"))
        populateCameraMenu(menu)
        return menu
    }

    private func populateCameraMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let cameras = CameraManager.shared.availableCameras
        let currentId = CameraManager.shared.currentCamera?.uniqueID

        if cameras.isEmpty {
            let emptyItem = NSMenuItem(
                title: String(localized: "No cameras available"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for (index, camera) in cameras.enumerated() {
            let item = NSMenuItem(
                title: camera.localizedName,
                action: #selector(cameraMenuItemClicked(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            item.target = self
            item.tag = index
            item.state = camera.uniqueID == currentId ? .on : .off
            menu.addItem(item)
        }
    }

    private func updateCameraMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              mainMenu.items.count > 1,
              let cameraMenu = mainMenu.items[1].submenu
        else { return }

        populateCameraMenu(cameraMenu)
    }

    @objc private func cameraMenuItemClicked(_ sender: NSMenuItem) {
        let cameras = CameraManager.shared.availableCameras
        guard sender.tag < cameras.count else { return }
        CameraManager.shared.switchCamera(to: cameras[sender.tag])
    }

    // MARK: - About

    @objc private func showAboutPanel(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        let description = String(localized: "A minimal floating camera overlay for macOS.\nPerfect for screen recordings.")

        let credits = NSAttributedString(
            string: description,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Boreal",
            .applicationVersion: version,
            .version: "",
            .credits: credits,
            .applicationIcon: NSApplication.shared.applicationIconImage as Any
        ])
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel = overlayWindow {
            panel.orderFrontRegardless()
        }
        return false
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCameraShortcut(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleCameraShortcut(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleCameraShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              let characters = event.charactersIgnoringModifiers,
              let digit = Int(characters),
              digit >= 1 && digit <= 9
        else {
            return false
        }

        let index = digit - 1
        let cameras = CameraManager.shared.availableCameras

        guard index < cameras.count else { return false }

        CameraManager.shared.switchCamera(to: cameras[index])
        return true
    }

    // MARK: - Window

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
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

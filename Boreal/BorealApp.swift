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
    var controlsWindow: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var recordingToggleItem: NSMenuItem?

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

        ScreenRecorder.shared.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in self?.updateRecordingToggleItem(isRecording: isRecording) }
            .store(in: &cancellables)

        ScreenRecorder.shared.$resolution
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateRecordingSettingsMenu() }
            .store(in: &cancellables)

        ScreenRecorder.shared.$fps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateRecordingSettingsMenu() }
            .store(in: &cancellables)

        ScreenRecorder.shared.$recordSystemAudio
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateRecordingSettingsMenu() }
            .store(in: &cancellables)

        ScreenRecorder.shared.$recordMicrophone
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateRecordingSettingsMenu() }
            .store(in: &cancellables)

        MicrophoneManager.shared.$availableMicrophones
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMicrophoneMenu() }
            .store(in: &cancellables)

        MicrophoneManager.shared.$currentMicrophone
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMicrophoneMenu() }
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

        let microphoneMenuItem = NSMenuItem()
        microphoneMenuItem.submenu = buildMicrophoneMenu()
        mainMenu.addItem(microphoneMenuItem)

        let recordingMenuItem = NSMenuItem()
        recordingMenuItem.submenu = buildRecordingMenu()
        mainMenu.addItem(recordingMenuItem)

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

    // MARK: - Recording Menu

    private func buildRecordingMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Record"))

        let resolutionItem = NSMenuItem(title: String(localized: "Resolution"), action: nil, keyEquivalent: "")
        resolutionItem.submenu = buildResolutionSubmenu()
        menu.addItem(resolutionItem)

        let fpsItem = NSMenuItem(title: "FPS", action: nil, keyEquivalent: "")
        fpsItem.submenu = buildFPSSubmenu()
        menu.addItem(fpsItem)

        menu.addItem(.separator())

        let systemAudioItem = NSMenuItem(
            title: String(localized: "System Audio"),
            action: #selector(toggleSystemAudio(_:)),
            keyEquivalent: ""
        )
        systemAudioItem.target = self
        systemAudioItem.state = ScreenRecorder.shared.recordSystemAudio ? .on : .off
        menu.addItem(systemAudioItem)

        let micItem = NSMenuItem(
            title: String(localized: "Microphone"),
            action: #selector(toggleMicrophone(_:)),
            keyEquivalent: ""
        )
        micItem.target = self
        micItem.state = ScreenRecorder.shared.recordMicrophone ? .on : .off
        menu.addItem(micItem)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: String(localized: "Start Recording"),
            action: #selector(toggleRecording(_:)),
            keyEquivalent: "r"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)

        self.recordingToggleItem = toggleItem

        return menu
    }

    private func buildResolutionSubmenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Resolution"))
        let current = ScreenRecorder.shared.resolution
        for res in RecordingResolution.allCases {
            let item = NSMenuItem(title: res.localizedName, action: #selector(resolutionMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = res
            item.state = res == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildFPSSubmenu() -> NSMenu {
        let menu = NSMenu(title: "FPS")
        let current = ScreenRecorder.shared.fps
        for fps in RecordingFPS.allCases {
            let item = NSMenuItem(title: fps.localizedName, action: #selector(fpsMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = fps
            item.state = fps == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func updateRecordingToggleItem(isRecording: Bool) {
        recordingToggleItem?.title = isRecording
            ? String(localized: "Stop Recording")
            : String(localized: "Start Recording")
    }

    private func updateRecordingSettingsMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              mainMenu.items.count > 3,
              let recordingMenu = mainMenu.items[3].submenu
        else { return }

        if let resSubmenu = recordingMenu.items.first?.submenu {
            let current = ScreenRecorder.shared.resolution
            for item in resSubmenu.items {
                if let r = item.representedObject as? RecordingResolution {
                    item.state = r == current ? .on : .off
                }
            }
        }

        if recordingMenu.items.count > 1, let fpsSubmenu = recordingMenu.items[1].submenu {
            let current = ScreenRecorder.shared.fps
            for item in fpsSubmenu.items {
                if let f = item.representedObject as? RecordingFPS {
                    item.state = f == current ? .on : .off
                }
            }
        }

        // Items: 0=Resolution, 1=FPS, 2=separator, 3=SystemAudio, 4=Microphone, 5=separator, ...
        if recordingMenu.items.count > 3 {
            recordingMenu.items[3].state = ScreenRecorder.shared.recordSystemAudio ? .on : .off
        }
        if recordingMenu.items.count > 4 {
            recordingMenu.items[4].state = ScreenRecorder.shared.recordMicrophone ? .on : .off
        }
    }

    @objc private func toggleRecording(_ sender: NSMenuItem) {
        if ScreenRecorder.shared.isRecording {
            ScreenRecorder.shared.stopRecording()
        } else {
            ScreenRecorder.shared.startRecording()
        }
    }

    @objc private func toggleSystemAudio(_ sender: NSMenuItem) {
        ScreenRecorder.shared.recordSystemAudio.toggle()
    }

    @objc private func toggleMicrophone(_ sender: NSMenuItem) {
        ScreenRecorder.shared.recordMicrophone.toggle()
    }

    @objc private func resolutionMenuItemClicked(_ sender: NSMenuItem) {
        guard let res = sender.representedObject as? RecordingResolution else { return }
        ScreenRecorder.shared.resolution = res
    }

    @objc private func fpsMenuItemClicked(_ sender: NSMenuItem) {
        guard let fps = sender.representedObject as? RecordingFPS else { return }
        ScreenRecorder.shared.fps = fps
    }

    // MARK: - Camera Menu

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

    // MARK: - Microphone Menu

    private func buildMicrophoneMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Microphone"))
        populateMicrophoneMenu(menu)
        return menu
    }

    private func populateMicrophoneMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let mics = MicrophoneManager.shared.availableMicrophones
        let currentId = MicrophoneManager.shared.currentMicrophone?.uniqueID

        if mics.isEmpty {
            let emptyItem = NSMenuItem(
                title: String(localized: "No microphones available"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for (index, mic) in mics.enumerated() {
            let item = NSMenuItem(
                title: mic.localizedName,
                action: #selector(microphoneMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = mic.uniqueID == currentId ? .on : .off
            menu.addItem(item)
        }
    }

    private func updateMicrophoneMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              mainMenu.items.count > 2,
              let micMenu = mainMenu.items[2].submenu
        else { return }

        populateMicrophoneMenu(micMenu)
    }

    @objc private func microphoneMenuItemClicked(_ sender: NSMenuItem) {
        let mics = MicrophoneManager.shared.availableMicrophones
        guard sender.tag < mics.count else { return }
        MicrophoneManager.shared.switchMicrophone(to: mics[sender.tag])
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
        // controlsWindow é filho — segue automaticamente
    }

    func createOverlayWindow() {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 320, height: 240)
        let controlsHeight: CGFloat = 44
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

        // Controls window — sharingType = .none exclui da captura de tela
        // Janela independente (não childWindow) para preservar o sharingType
        let controlsFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - controlsHeight - 4,
            width: windowSize.width,
            height: controlsHeight
        )

        let controlsPanel = NSPanel(
            contentRect: controlsFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        controlsPanel.sharingType = .none
        controlsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controlsPanel.level = .floating
        controlsPanel.isFloatingPanel = true
        controlsPanel.hidesOnDeactivate = false
        controlsPanel.isOpaque = false
        controlsPanel.backgroundColor = .clear
        controlsPanel.hasShadow = false

        let controlsHostingView = NSHostingView(rootView: RecordingControlsView())
        controlsHostingView.frame = NSRect(origin: .zero, size: CGSize(width: windowSize.width, height: controlsHeight))
        controlsPanel.contentView = controlsHostingView

        // addChildWindow move em sincronia perfeita — exclusão da gravação é feita
        // pelo SCContentFilter do ScreenCaptureKit pelo windowID, não pelo sharingType
        panel.addChildWindow(controlsPanel, ordered: .above)
        panel.orderFrontRegardless()

        self.overlayWindow = panel
        self.controlsWindow = controlsPanel

        // Informa o ID da janela de controles ao ScreenRecorder para excluí-la da captura
        ScreenRecorder.shared.controlsWindowID = CGWindowID(controlsPanel.windowNumber)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

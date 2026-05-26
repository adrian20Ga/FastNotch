import AppKit
import os

private let bundleIdentifier = "com.adriangonzalez.FastNotch"
private let logger = Logger(subsystem: bundleIdentifier, category: "app")

struct NotchItem: Equatable {
    let title: String
    let bundleIdentifier: String?
    let url: URL?

    static let defaults = [
        NotchItem(title: "Finder", bundleIdentifier: "com.apple.finder", url: nil),
        NotchItem(title: "Chrome", bundleIdentifier: "com.google.Chrome", url: nil),
        NotchItem(title: "Safari", bundleIdentifier: "com.apple.Safari", url: nil),
        NotchItem(title: "Notes", bundleIdentifier: "com.apple.Notes", url: nil),
        NotchItem(title: "Terminal", bundleIdentifier: "com.apple.Terminal", url: nil),
        NotchItem(title: "Settings", bundleIdentifier: "com.apple.systempreferences", url: nil)
    ]
}

enum InteractionMode: String {
    case hover
    case click

    var title: String {
        switch self {
        case .hover: "Open on Hover"
        case .click: "Open on Click"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var hoverModeItem: NSMenuItem?
    private var clickModeItem: NSMenuItem?
    private var appMenuItems: [String: NSMenuItem] = [:]
    private var customAppMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIcon.make()

        let controller = NotchController()
        self.controller = controller
        controller.show()
        setupStatusItem()
        logger.info("FastNotch launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.hideActiveItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppIcon.menuImage()
        item.button?.imagePosition = .imageOnly
        item.menu = makeMenu()
        statusItem = item
        if let url = controller?.activeCustomURL {
            updateCustomAppMenu(url: url)
            updateSelectedAppMenu()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "FastNotch", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        let hover = NSMenuItem(title: InteractionMode.hover.title, action: #selector(setHoverMode), keyEquivalent: "")
        hover.target = self
        let click = NSMenuItem(title: InteractionMode.click.title, action: #selector(setClickMode), keyEquivalent: "")
        click.target = self
        settingsMenu.addItem(hover)
        settingsMenu.addItem(click)
        settings.submenu = settingsMenu
        hoverModeItem = hover
        clickModeItem = click
        menu.addItem(settings)
        menu.addItem(.separator())

        for notchItem in NotchItem.defaults {
            let menuItem = NSMenuItem(title: notchItem.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = notchItem.bundleIdentifier
            appMenuItems[notchItem.bundleIdentifier ?? notchItem.title] = menuItem
            menu.addItem(menuItem)
        }
        let customItem = NSMenuItem(title: "", action: #selector(selectCustomApp(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.isHidden = true
        menu.addItem(customItem)
        customAppMenuItem = customItem

        menu.addItem(.separator())
        let choose = NSMenuItem(title: "Choose App or Shortcut...", action: #selector(chooseItem), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        updateModeMenu()
        updateSelectedAppMenu()
        return menu
    }

    @objc private func setHoverMode() {
        controller?.setInteractionMode(.hover)
        updateModeMenu()
    }

    @objc private func setClickMode() {
        controller?.setInteractionMode(.click)
        updateModeMenu()
    }

    private func updateModeMenu() {
        let mode = controller?.interactionMode ?? .hover
        hoverModeItem?.state = mode == .hover ? .on : .off
        clickModeItem?.state = mode == .click ? .on : .off
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller?.selectBundleIdentifier(id)
        updateSelectedAppMenu()
    }

    @objc private func chooseItem() {
        let panel = NSOpenPanel()
        panel.title = "Choose App or Shortcut"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.controller?.selectURL(url)
                self?.updateCustomAppMenu(url: url)
                self?.updateSelectedAppMenu()
            }
        }
    }

    private func updateSelectedAppMenu() {
        let activeKey = controller?.activeMenuKey
        for (key, item) in appMenuItems {
            item.state = key == activeKey ? .on : .off
        }
        customAppMenuItem?.state = customAppMenuItem?.representedObject as? String == activeKey ? .on : .off
    }

    private func updateCustomAppMenu(url: URL) {
        let key = url.path
        let title = url.deletingPathExtension().lastPathComponent
        if customAppMenuItem == nil {
            let item = NSMenuItem(title: title, action: #selector(selectCustomApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            statusItem?.menu?.addItem(item)
            customAppMenuItem = item
        }
        customAppMenuItem?.title = title
        customAppMenuItem?.representedObject = key
        customAppMenuItem?.isHidden = false
    }

    @objc private func selectCustomApp(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        controller?.selectURL(URL(fileURLWithPath: path))
        updateSelectedAppMenu()
    }
}

@MainActor
final class NotchController: NSObject {
    private let launcher = ItemLauncher()
    private var notchPanels: [UInt32: NSPanel] = [:]
    private var activeItem: NotchItem
    private var shownItem: NotchItem?
    private var lastShowDate = Date.distantPast
    private var pendingHoverWorkItem: DispatchWorkItem?
    private(set) var interactionMode: InteractionMode
    var activeMenuKey: String { activeItem.bundleIdentifier ?? activeItem.url?.path ?? activeItem.title }
    var activeCustomURL: URL? { activeItem.url }

    override init() {
        activeItem = Self.loadSavedItem()
        interactionMode = Self.loadInteractionMode()
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        rebuildPanels()
    }

    func selectBundleIdentifier(_ id: String) {
        guard let item = NotchItem.defaults.first(where: { $0.bundleIdentifier == id }) else { return }
        activeItem = item
        saveActiveItem()
    }

    func selectURL(_ url: URL) {
        activeItem = NotchItem(title: url.deletingPathExtension().lastPathComponent, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, url: url)
        saveActiveItem()
    }

    func setInteractionMode(_ mode: InteractionMode) {
        interactionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "interactionMode")
    }

    func hideActiveItem() {
        hideShownItem()
    }

    @objc private func activeSpaceDidChange() {
        pendingHoverWorkItem?.cancel()
        pendingHoverWorkItem = nil
        shownItem = nil
        setPanelsExpanded(false)
        rebuildPanels()
    }

    @objc private func screenParametersDidChange() {
        rebuildPanels()
    }

    private func toggleActiveItem() {
        if interactionMode == .hover, shownItem != nil, Date().timeIntervalSince(lastShowDate) < 0.35 {
            return
        }
        shownItem == nil ? showItem(activeItem) : hideShownItem()
    }

    private func showActiveItemFromHover() {
        guard interactionMode == .hover else { return }
        if let pendingHoverWorkItem {
            pendingHoverWorkItem.cancel()
            self.pendingHoverWorkItem = nil
            toggleFinderQuickAction()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pendingHoverWorkItem = nil
                guard let self else { return }
                self.shownItem == nil ? self.showItem(self.activeItem) : self.hideShownItem()
            }
        }
        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: workItem)
    }

    private func toggleFinderQuickAction() {
        let finder = NotchItem.defaults[0]
        if shownItem == finder {
            launcher.hide(finder, restoresPreviousApp: true)
            shownItem = nil
            setPanelsExpanded(false)
            return
        }
        if let item = shownItem {
            launcher.hide(item, restoresPreviousApp: false)
            shownItem = nil
        }
        shownItem = finder
        lastShowDate = Date()
        setPanelsExpanded(true)
        launcher.showFinderQuickAction()
    }

    private func showItem(_ item: NotchItem) {
        guard shownItem == nil else { return }
        shownItem = item
        lastShowDate = Date()
        setPanelsExpanded(true)
        launcher.show(item)
    }

    private func hideShownItem() {
        guard let item = shownItem else { return }
        launcher.hide(item, restoresPreviousApp: true)
        shownItem = nil
        setPanelsExpanded(false)
    }

    private func rebuildPanels() {
        let currentIDs = Set(NSScreen.screens.compactMap { Self.screenID(for: $0) })
        let staleIDs = notchPanels.keys.filter { !currentIDs.contains($0) }
        for id in staleIDs {
            notchPanels[id]?.orderOut(nil)
            notchPanels.removeValue(forKey: id)
        }

        for screen in NSScreen.screens {
            guard let id = Self.screenID(for: screen) else { continue }
            let panel = notchPanels[id] ?? Self.makePanel()
            if notchPanels[id] == nil {
                let view = NotchView(frame: NSRect(origin: .zero, size: Self.notchSize))
                view.onToggle = { [weak self] in self?.toggleActiveItem() }
                view.onHoverOpen = { [weak self] in self?.showActiveItemFromHover() }
                panel.contentView = view
                notchPanels[id] = panel
            }
            position(panel: panel, on: screen)
            (panel.contentView as? NotchView)?.setExpanded(shownItem != nil)
            panel.orderFrontRegardless()
        }
    }

    private func position(panel: NSPanel, on screen: NSScreen) {
        let frame = screen.frame
        let notchX = frame.midX - Self.notchSize.width / 2
        let notchY = frame.maxY - Self.notchSize.height + 1
        panel.setFrame(NSRect(origin: NSPoint(x: notchX, y: notchY), size: Self.notchSize), display: true)
    }

    private func setPanelsExpanded(_ expanded: Bool) {
        notchPanels.values.forEach { panel in
            (panel.contentView as? NotchView)?.setExpanded(expanded)
        }
    }

    private func saveActiveItem() {
        let defaults = UserDefaults.standard
        defaults.set(activeItem.title, forKey: "activeTitle")
        defaults.set(activeItem.bundleIdentifier, forKey: "activeBundleIdentifier")
        defaults.set(activeItem.url?.path, forKey: "activePath")
    }

    private static func loadSavedItem() -> NotchItem {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "activePath") {
            let url = URL(fileURLWithPath: path)
            return NotchItem(title: defaults.string(forKey: "activeTitle") ?? url.lastPathComponent, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, url: url)
        }
        if let id = defaults.string(forKey: "activeBundleIdentifier"),
           let item = NotchItem.defaults.first(where: { $0.bundleIdentifier == id }) {
            return item
        }
        return NotchItem.defaults[0]
    }

    private static func loadInteractionMode() -> InteractionMode {
        guard let rawValue = UserDefaults.standard.string(forKey: "interactionMode"),
              let mode = InteractionMode(rawValue: rawValue) else {
            return .hover
        }
        return mode
    }

    private static let notchSize = NSSize(width: 210, height: 32)

    private static func screenID(for screen: NSScreen) -> UInt32? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: notchSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

final class ItemLauncher {
    private var previousBundleIdentifier: String?

    func show(_ item: NotchItem) {
        if let url = item.url {
            rememberFrontmostApp(excluding: item.bundleIdentifier)
            NSWorkspace.shared.open(url)
            return
        }
        guard let id = item.bundleIdentifier else { return }
        rememberFrontmostApp(excluding: id)
        if id == "com.apple.finder" {
            showFinder()
            return
        }

        if let runningApp = runningApplication(bundleIdentifier: id) {
            runningApp.unhide()
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL(for: id), configuration: configuration)
    }

    func hide(_ item: NotchItem, restoresPreviousApp: Bool) {
        guard let id = item.bundleIdentifier else { return }
        if id == "com.apple.finder" {
            hideFinder(restoresPreviousApp: restoresPreviousApp)
            return
        }

        let returnTarget = restoresPreviousApp ? previousBundleIdentifier : nil
        if restoresPreviousApp {
            previousBundleIdentifier = nil
        }

        runningApplication(bundleIdentifier: id)?.hide()
        if let returnTarget {
            activateAfterDelay(bundleIdentifier: returnTarget)
        }
    }

    func showFinderQuickAction() {
        rememberFrontmostApp(excluding: "com.apple.finder")
        if hasFinderWindowInCurrentSpace() {
            activateFinder()
        } else {
            openFinderHome()
        }
    }

    func hideFinderQuickAction() {
        let source = """
        tell application "Finder"
            if exists Finder window 1 then
                close front Finder window
            end if
        end tell
        """
        runScript(source, qos: .utility)
    }

    private func applicationURL(for bundleIdentifier: String) -> URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    }

    private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func showFinder() {
        if hasFinderWindowInCurrentSpace() {
            activateFinder()
        } else {
            openFinderHome()
        }
    }

    private func hideFinder(restoresPreviousApp: Bool) {
        let returnTarget = restoresPreviousApp ? previousBundleIdentifier : nil
        if restoresPreviousApp {
            previousBundleIdentifier = nil
        }

        let source = """
        tell application "Finder"
            if exists Finder window 1 then
                close front Finder window
            end if
        end tell
        """
        runScript(source, qos: .utility)
        if let returnTarget {
            activateAfterDelay(bundleIdentifier: returnTarget)
        }
    }

    private func rememberFrontmostApp(excluding excludedBundleIdentifier: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != "com.apple.finder",
              bundleIdentifier != "com.adriangonzalez.FastNotch",
              bundleIdentifier != excludedBundleIdentifier else {
            return
        }
        previousBundleIdentifier = bundleIdentifier
    }

    private func hasFinderWindowInCurrentSpace() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windowList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Finder",
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else {
                return false
            }
            return width > 80 && height > 80
        }
    }

    private func activateFinder() {
        if let finder = runningApplication(bundleIdentifier: "com.apple.finder") {
            finder.unhide()
            finder.activate(options: [.activateAllWindows])
        } else {
            NSWorkspace.shared.openApplication(at: applicationURL(for: "com.apple.finder"), configuration: .init())
        }
    }

    private func openFinderHome() {
        let source = """
        tell application "Finder"
            make new Finder window to home
            activate
        end tell
        """
        runScript(source, qos: .userInitiated)
    }

    private func activate(bundleIdentifier: String) {
        let source = """
        tell application id "\(bundleIdentifier)"
            activate
        end tell
        """
        runScript(source, qos: .userInitiated)
    }

    private func activateAfterDelay(bundleIdentifier: String) {
        let source = """
        delay 0.05
        tell application id "\(bundleIdentifier)"
            activate
        end tell
        """
        runScript(source, qos: .utility)
    }

    private func runScript(_ source: String, qos: DispatchQoS.QoSClass) {
        DispatchQueue.global(qos: qos).async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                logger.error("AppleScript failed: \(errorInfo.description, privacy: .public)")
            }
        }
    }
}

final class NotchView: NSView {
    var onToggle: (() -> Void)?
    var onHoverOpen: (() -> Void)?

    private var isHovered = false
    private var isExpanded = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        setNeedsDisplay(bounds)
        onHoverOpen?()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        onToggle?()
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        alphaValue = expanded ? 0.96 : 0.88
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        (isExpanded ? NSColor(calibratedWhite: 0.035, alpha: 0.98) : .black).setFill()
        path.fill()
    }
}

enum AppIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 40, width: 100, height: 48), xRadius: 22, yRadius: 22).fill()
        image.unlockFocus()
        return image
    }

    static func menuImage() -> NSImage {
        let image = make()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

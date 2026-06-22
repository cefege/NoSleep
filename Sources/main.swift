import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var stateMenuItem: NSMenuItem!
    var toggleMenuItem: NSMenuItem!
    var silentMenuItem: NSMenuItem!
    var toggleButton: NSButton!
    var statusLabel: NSTextField!
    var hintLabel: NSTextField!
    var autoEnableCheckbox: NSButton!
    var loginCheckbox: NSButton!
    var sleepDisabled = false
    var isToggling = false
    var pollTimer: Timer?
    var autoOffTimer: Timer?
    var autoOffDeadline: Date?
    let autoEnableKey = "autoEnableOnLaunch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkCurrentState()
        setupWindow()
        updateUI()

        // First launch defaults
        if UserDefaults.standard.object(forKey: autoEnableKey) == nil {
            UserDefaults.standard.set(true, forKey: autoEnableKey)
            autoEnableCheckbox.state = .on
        }

        // Just reflect the real login-item state — let the checkbox control it.
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Auto-enable after a short delay (only if not already disabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if UserDefaults.standard.bool(forKey: self.autoEnableKey) && !self.sleepDisabled {
                self.toggle()
            }
        }

        // Poll every 30s to keep UI in sync with actual state
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkCurrentState()
            self?.updateUI()
        }
    }

    func setupWindow() {
        let width: CGFloat = 340
        let height: CGFloat = 260

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoSleep"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        statusLabel = NSTextField(frame: NSRect(x: 15, y: 195, width: 310, height: 50))
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.alignment = .center
        statusLabel.font = NSFont.boldSystemFont(ofSize: 14)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.cell?.wraps = true
        statusLabel.cell?.truncatesLastVisibleLine = false
        contentView.addSubview(statusLabel)

        toggleButton = NSButton(frame: NSRect(x: 80, y: 155, width: 180, height: 32))
        toggleButton.bezelStyle = .rounded
        toggleButton.target = self
        toggleButton.action = #selector(toggleClicked)
        contentView.addSubview(toggleButton)

        hintLabel = NSTextField(frame: NSRect(x: 15, y: 105, width: 310, height: 45))
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.backgroundColor = .clear
        hintLabel.alignment = .center
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 3
        hintLabel.cell?.wraps = true
        hintLabel.cell?.truncatesLastVisibleLine = false
        contentView.addSubview(hintLabel)

        autoEnableCheckbox = NSButton(checkboxWithTitle: "Auto-enable on launch", target: self, action: #selector(autoEnableClicked))
        autoEnableCheckbox.frame = NSRect(x: 30, y: 65, width: 280, height: 20)
        autoEnableCheckbox.state = UserDefaults.standard.bool(forKey: autoEnableKey) ? .on : .off
        contentView.addSubview(autoEnableCheckbox)

        loginCheckbox = NSButton(checkboxWithTitle: "Open at Login", target: self, action: #selector(loginItemClicked))
        loginCheckbox.frame = NSRect(x: 30, y: 38, width: 280, height: 20)
        contentView.addSubview(loginCheckbox)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        stateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "", action: #selector(toggleClicked), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        for hours in [1.0, 2.0] {
            let label = "Keep awake for \(Int(hours)) hour\(hours == 1 ? "" : "s"), then auto-off"
            let item = NSMenuItem(title: label, action: #selector(keepAwakeClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hours
            menu.addItem(item)
        }
        menu.addItem(.separator())

        silentMenuItem = NSMenuItem(title: "", action: #selector(silentModeClicked), keyEquivalent: "")
        silentMenuItem.target = self
        menu.addItem(silentMenuItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open NoSleep Window", action: #selector(showWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit NoSleep", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // Refresh from the real pmset state right before the menu shows — bulletproof against drift.
    func menuNeedsUpdate(_ menu: NSMenu) {
        checkCurrentState()
        updateUI()
    }

    @objc func showWindow() {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func updateUI() {
        if sleepDisabled {
            statusLabel.stringValue = "Now: Closing the lid will NOT\ndisconnect your apps"
            statusLabel.textColor = .systemGreen
            toggleButton.title = "Stop protecting"
            hintLabel.stringValue = "Pressing this will let your Mac sleep\nwhen you close the lid.\nApps like Citrix will disconnect."
        } else {
            statusLabel.stringValue = "Now: Closing the lid WILL\ndisconnect your apps"
            statusLabel.textColor = .systemRed
            toggleButton.title = "Start protecting"
            hintLabel.stringValue = "Pressing this will keep your Mac awake\nwhen you close the lid.\nApps like Citrix will stay connected."
        }
        toggleButton.isEnabled = !isToggling
        if isToggling {
            toggleButton.title = "Toggling..."
        }

        // Menu bar icon + menu wording. ON = Mac can't sleep, OFF = Mac can sleep.
        if sleepDisabled {
            statusItem?.button?.title = "☕️"
            statusItem?.button?.toolTip = "NoSleep is ON — your Mac will not sleep"
            var state = "ON — Mac CANNOT sleep (lid close is safe)"
            if let deadline = autoOffDeadline {
                let f = DateFormatter()
                f.timeStyle = .short
                state += "\nAuto-off at \(f.string(from: deadline))"
            }
            stateMenuItem?.title = state
            toggleMenuItem?.title = "Turn OFF (let Mac sleep)"
        } else {
            statusItem?.button?.title = "💤"
            statusItem?.button?.toolTip = "NoSleep is OFF — your Mac can sleep"
            stateMenuItem?.title = "OFF — Mac CAN sleep (lid close disconnects apps)"
            toggleMenuItem?.title = "Turn ON (keep Mac awake)"
        }
        if isToggling {
            stateMenuItem?.title = "Switching…"
            toggleMenuItem?.title = "Switching…"
        }
        toggleMenuItem?.action = isToggling ? nil : #selector(toggleClicked)

        silentMenuItem?.title = silentInstalled
            ? "Silent toggling: ON (click to disable)"
            : "Enable silent toggling (no more passwords)…"
    }

    // Reopen window when clicking dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    func checkCurrentState() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        sleepDisabled = output.range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
    }

    @objc func toggleClicked() {
        cancelAutoOff()
        toggle()
    }

    @objc func keepAwakeClicked(_ sender: NSMenuItem) {
        let hours = sender.representedObject as? Double ?? 1
        autoOffTimer?.invalidate()
        autoOffDeadline = Date().addingTimeInterval(hours * 3600)
        autoOffTimer = Timer.scheduledTimer(withTimeInterval: hours * 3600, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.autoOffTimer = nil
            self.autoOffDeadline = nil
            if self.sleepDisabled { self.toggle() }  // revert (prompts for password)
            self.updateUI()
        }
        if !sleepDisabled { toggle() }  // turn on now
        updateUI()
    }

    func cancelAutoOff() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        autoOffDeadline = nil
    }

    func toggle() {
        guard !isToggling else { return }
        isToggling = true
        updateUI()

        let newValue = sleepDisabled ? "0" : "1"
        let previousState = sleepDisabled

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failed = !Self.runSudoNoPassword(newValue)
            // Fall back to the GUI password prompt if silent mode isn't installed.
            if failed {
                let script = "do shell script \"pmset -a disablesleep \(newValue)\" with administrator privileges"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    failed = task.terminationStatus != 0
                } catch {
                    failed = true
                }
            }

            DispatchQueue.main.async {
                self?.checkCurrentState()
                self?.isToggling = false
                self?.updateUI()

                // If state didn't change, the user cancelled or entered wrong password
                if failed && self?.sleepDisabled == previousState {
                    let alert = NSAlert()
                    alert.messageText = "Failed to toggle sleep"
                    alert.informativeText = "Authentication was cancelled or the password was incorrect."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    static let sudoersPath = "/etc/sudoers.d/nosleep"

    // Silent toggle via passwordless sudo. Returns false if the sudoers rule isn't installed.
    static func runSudoNoPassword(_ value: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    var silentInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    @objc func silentModeClicked() {
        if silentInstalled {
            // Remove the rule.
            runAdmin("rm -f \(Self.sudoersPath)")
        } else {
            // Write a temp file, then install it root-owned 0440 and validate; bad syntax self-deletes.
            let user = NSUserName()
            let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
            let tmp = NSTemporaryDirectory() + "nosleep.sudoers"
            try? rule.write(toFile: tmp, atomically: true, encoding: .utf8)
            runAdmin("install -m 0440 -o root -g wheel '\(tmp)' \(Self.sudoersPath) && visudo -cf \(Self.sudoersPath) || rm -f \(Self.sudoersPath)")
            try? FileManager.default.removeItem(atPath: tmp)
        }
        updateUI()
    }

    // One admin prompt to run a shell command as root.
    func runAdmin(_ command: String) {
        let script = "do shell script \"\(command)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    @objc func autoEnableClicked() {
        UserDefaults.standard.set(autoEnableCheckbox.state == .on, forKey: autoEnableKey)
    }

    @objc func loginItemClicked() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {}
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        autoOffTimer?.invalidate()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

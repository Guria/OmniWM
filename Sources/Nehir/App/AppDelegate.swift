import AppKit
import Observation

@MainActor @Observable
final class AppBootstrapState {
    var settings: SettingsStore?
    var controller: WMController?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) weak static var sharedBootstrap: AppBootstrapState?
    static var ipcServerFactoryForTests: ((WMController) -> IPCServerLifecycle)?

    private var statusBarController: StatusBarController?
    private var ipcServer: IPCServerLifecycle?
    private var cliManager: AppCLIManager?
    private var runtimeStateStore: RuntimeStateStore?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        bootstrapApplication()
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_: Notification) {
        if let controller = AppDelegate.sharedBootstrap?.controller {
            controller.serviceLifecycleManager.stop()
            controller.workspaceManager.flushPersistedWindowRestoreCatalogNow()
        }
        AppDelegate.sharedBootstrap?.settings?.flushNow()
        stopIPCServer()
        runtimeStateStore?.flushNow()
    }

    func bootstrapApplication() {
        switch AppBootstrapPlanner.decision() {
        case .boot:
            finishBootstrap()
        }
    }

    func finishBootstrap() {
        let storagePaths = NehirStoragePaths.live

        // One-time migration from OmniWM config
        migrateOmniWMSettingsIfNeeded(to: storagePaths.configDirectory)

        let runtimeState = RuntimeStateStore(directory: storagePaths.stateDirectory)
        self.runtimeStateStore = runtimeState

        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: storagePaths.configDirectory),
            runtimeState: runtimeState
        )
        let hiddenBarController = HiddenBarController(settings: settings)
        let controller = WMController(
            settings: settings,
            hiddenBarController: hiddenBarController,
            clipboardHistoryDirectory: storagePaths.stateDirectory
        )
        controller.applyPersistedSettings(settings)
        let cliManager = AppCLIManager()
        self.cliManager = cliManager

        AppDelegate.sharedBootstrap?.settings = settings
        AppDelegate.sharedBootstrap?.controller = controller

        statusBarController = StatusBarController(
            settings: settings,
            controller: controller,
            hiddenBarController: hiddenBarController,
            cliManager: cliManager,
        )
        controller.statusBarController = statusBarController
        settings.onIPCEnabledChanged = { [weak self, weak controller] isEnabled in
            guard let self, let controller else { return }
            do {
                try self.setIPCEnabled(isEnabled, controller: controller)
            } catch {
                self.presentInfoAlert(
                    title: "IPC Failed to Start",
                    message: error.localizedDescription
                )
                if isEnabled {
                    settings.ipcEnabled = false
                }
            }
            self.statusBarController?.refreshMenu()
        }
        settings.onExternalSettingsReloaded = { [weak controller, weak self] in
            guard let controller else { return }
            controller.applyPersistedSettings(settings)
            self?.statusBarController?.refreshMenu()
        }
        statusBarController?.setup()
        do {
            try setIPCEnabled(settings.ipcEnabled, controller: controller)
        } catch {
            presentInfoAlert(
                title: "IPC Failed to Start",
                message: error.localizedDescription
            )
            settings.ipcEnabled = false
        }
    }

    func startIPCServer(controller: WMController) throws {
        if ipcServer != nil {
            stopIPCServer()
        }
        let server = Self.ipcServerFactoryForTests?(controller) ?? IPCServer(controller: controller)
        try server.start()
        ipcServer = server
    }

    func setIPCEnabled(_ enabled: Bool, controller: WMController) throws {
        if enabled {
            try startIPCServer(controller: controller)
        } else {
            stopIPCServer()
        }
    }

    private func stopIPCServer() {
        ipcServer?.stop()
        ipcServer = nil
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = alert.runModal()
    }

    /// Migrates settings from `~/.config/omniwm/settings.toml` to the Nehir config directory
    /// if no Nehir config exists yet. Strips the `[dwindle]` and `monitorDwindleOverrides`
    /// sections since they are no longer supported.
    private func migrateOmniWMSettingsIfNeeded(to nehirConfigDir: URL) {
        let nehirSettings = nehirConfigDir.appendingPathComponent("settings.toml")
        guard !FileManager.default.fileExists(atPath: nehirSettings.path) else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let omniwmSettings = home
            .appendingPathComponent(".config/omniwm/settings.toml")

        guard FileManager.default.fileExists(atPath: omniwmSettings.path),
              let content = try? String(contentsOf: omniwmSettings, encoding: .utf8)
        else { return }

        // Strip [dwindle] section and monitorDwindleOverrides
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skipSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[dwindle]" {
                skipSection = true
                continue
            }
            if skipSection {
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[dwindle") {
                    skipSection = false
                } else {
                    continue
                }
            }
            if trimmed.hasPrefix("monitorDwindleOverrides") {
                continue
            }
            // Strip updateChecksEnabled since we removed updates
            if trimmed.hasPrefix("updateChecksEnabled") {
                continue
            }
            result.append(line)
        }

        let migrated = result.joined(separator: "\n")
            .replacingOccurrences(of: "Hyper+", with: "Modifier+")
            .replacingOccurrences(of: "\"Hyper\"", with: "\"Modifier\"")
        do {
            try FileManager.default.createDirectory(at: nehirConfigDir, withIntermediateDirectories: true)
            try migrated.write(to: nehirSettings, atomically: true, encoding: .utf8)
            NSLog("Nehir: Migrated settings from ~/.config/omniwm/settings.toml")
        } catch {
            NSLog("Nehir: Failed to migrate OmniWM settings: \(error.localizedDescription)")
        }
    }
}

import AppKit
import Foundation
import GhosttyKit
@testable import Nehir
import Testing

private func makeQuakeTerminalTestDefaults() -> UserDefaults {
    let suiteName = "com.nehir.quake-terminal-focus.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

@MainActor
private func makeQuakeTerminalTestController(
    autoHide: Bool = false,
    captureRestoreTarget: @escaping @MainActor () -> QuakeTerminalRestoreTarget?,
    restoreFocusTarget: @escaping @MainActor (QuakeTerminalRestoreTarget) -> Void,
    isWindowFocused: @escaping @MainActor (NSWindow) -> Bool
) -> QuakeTerminalController {
    let settings = SettingsStore(defaults: makeQuakeTerminalTestDefaults())
    settings.animationsEnabled = false
    settings.quakeTerminalUseCustomFrame = true
    settings.quakeTerminalAutoHide = autoHide

    return QuakeTerminalController(
        settings: settings,
        motionPolicy: MotionPolicy(animationsEnabled: false),
        captureRestoreTarget: captureRestoreTarget,
        restoreFocusTarget: restoreFocusTarget,
        isWindowFocused: isWindowFocused
    )
}

private func makeManagedRestoreTarget(
    pid: pid_t,
    windowId: Int
) -> QuakeTerminalRestoreTarget {
    .managed(WindowToken(pid: pid, windowId: windowId))
}

private func makeQuakeGhosttyConfigTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("nehir-quake-ghostty-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private final class QuakeGhosttyConfigRecorder: @unchecked Sendable {
    let config = UnsafeMutableRawPointer(bitPattern: 0x1234)!
    var steps: [QuakeGhosttyConfigLoadStep] = []
    var loadedOverridePaths: [String] = []
    var loadedOverrideContents: [String] = []
    var freedConfigCount = 0

    var operations: QuakeGhosttyConfigOperations {
        QuakeGhosttyConfigOperations(
            makeConfig: { self.config },
            loadDefaultFiles: { _ in },
            loadRecursiveFiles: { _ in },
            loadFile: { _, path in
                self.loadedOverridePaths.append(path)
                self.loadedOverrideContents.append(
                    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                )
            },
            finalize: { _ in },
            freeConfig: { _ in self.freedConfigCount += 1 },
            recordStep: { self.steps.append($0) }
        )
    }
}

private final class QuakeTerminalFocusBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
private func settleQuakeTerminalFocusUpdates() async {
    for _ in 0 ..< 5 {
        await Task.yield()
    }
}

@Suite struct QuakeGhosttyConfigTests {
    @Test func overrideContentUsesGhosttyConfigSyntax() {
        #expect(QuakeGhosttyConfigBuilder.overrideContent(opacity: 0.75) == "background-opacity = 0.75\n")
    }

    @Test func loadsGhosttyDefaultsBeforeQuakeOverride() throws {
        let directory = try makeQuakeGhosttyConfigTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = QuakeGhosttyConfigRecorder()
        let builder = QuakeGhosttyConfigBuilder(
            temporaryDirectory: directory,
            operations: recorder.operations
        )

        let config = try #require(builder.build(opacity: 0.75))

        #expect(config == recorder.config)
        #expect(recorder.steps == [.makeConfig, .loadDefaultFiles, .loadRecursiveFiles, .loadFile, .finalize])
        #expect(recorder.loadedOverrideContents == ["background-opacity = 0.75\n"])
        #expect(recorder.loadedOverridePaths.count == 1)
        #expect(recorder.loadedOverridePaths.first?.hasPrefix(directory.path) == true)
        #expect(FileManager.default.fileExists(atPath: try #require(recorder.loadedOverridePaths.first)) == false)
        #expect(recorder.freedConfigCount == 0)
    }

    @Test func doesNotMutateGhosttyUserConfig() throws {
        let directory = try makeQuakeGhosttyConfigTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ghosttyConfigDirectory = directory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("ghostty", isDirectory: true)
        let ghosttyConfigFile = ghosttyConfigDirectory.appendingPathComponent("config", isDirectory: false)
        let original = """
        font-family = JetBrainsMono Nerd Font
        background-opacity = 0.90
        theme = light:Catppuccin Latte,dark:Catppuccin Mocha

        """
        try FileManager.default.createDirectory(at: ghosttyConfigDirectory, withIntermediateDirectories: true)
        try original.write(to: ghosttyConfigFile, atomically: true, encoding: .utf8)

        let recorder = QuakeGhosttyConfigRecorder()
        let builder = QuakeGhosttyConfigBuilder(
            temporaryDirectory: directory.appendingPathComponent("omniwm", isDirectory: true),
            operations: recorder.operations
        )
        _ = try #require(builder.build(opacity: 1.0))

        #expect(try String(contentsOf: ghosttyConfigFile, encoding: .utf8) == original)
        #expect(recorder.loadedOverrideContents == ["background-opacity = 1.00\n"])
    }

    @Test @MainActor func colorSchemeFollowsEffectiveAppearance() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))

        #expect(QuakeTerminalController.ghosttyColorScheme(for: dark) == GHOSTTY_COLOR_SCHEME_DARK)
        #expect(QuakeTerminalController.ghosttyColorScheme(for: light) == GHOSTTY_COLOR_SCHEME_LIGHT)
    }
}

@Suite(.serialized) struct QuakeTerminalControllerTests {
    @Test @MainActor func manualCloseRestoresCapturedTargetWhenFocusNeverChanged() {
        let target = makeManagedRestoreTarget(pid: 41, windowId: 410)
        var restoredTargets: [QuakeTerminalRestoreTarget] = []
        let controller = makeQuakeTerminalTestController(
            captureRestoreTarget: { target },
            restoreFocusTarget: { restoredTargets.append($0) },
            isWindowFocused: { _ in true }
        )

        controller.configureTransitionStateForTests(visible: true, isTransitioning: false)
        controller.captureRestoreTargetForTests()
        controller.animateOut()

        #expect(restoredTargets == [target])
        #expect(controller.restoreTargetForTests == nil)
    }

    @Test @MainActor func focusLossRefreshesRestoreTargetToLatestWindowInSameApp() async {
        let appPid: pid_t = 52
        let initialTarget = makeManagedRestoreTarget(pid: appPid, windowId: 520)
        let refreshedTarget = makeManagedRestoreTarget(pid: appPid, windowId: 521)
        var currentTarget = initialTarget
        var restoredTargets: [QuakeTerminalRestoreTarget] = []
        let windowIsFocused = QuakeTerminalFocusBox(false)
        let controller = makeQuakeTerminalTestController(
            captureRestoreTarget: { currentTarget },
            restoreFocusTarget: { restoredTargets.append($0) },
            isWindowFocused: { _ in windowIsFocused.value }
        )

        controller.configureTransitionStateForTests(visible: true, isTransitioning: false)
        controller.captureRestoreTargetForTests()

        currentTarget = refreshedTarget
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        await settleQuakeTerminalFocusUpdates()

        #expect(controller.restoreTargetForTests == refreshedTarget)

        windowIsFocused.value = true
        controller.animateOut()

        #expect(restoredTargets == [refreshedTarget])
    }

    @Test @MainActor func manualCloseWhileQuakeIsNotFocusedDoesNotRestoreFocus() async {
        let initialTarget = makeManagedRestoreTarget(pid: 61, windowId: 610)
        let currentTarget = makeManagedRestoreTarget(pid: 62, windowId: 620)
        var observedTarget = initialTarget
        var restoredTargets: [QuakeTerminalRestoreTarget] = []
        let controller = makeQuakeTerminalTestController(
            captureRestoreTarget: { observedTarget },
            restoreFocusTarget: { restoredTargets.append($0) },
            isWindowFocused: { _ in false }
        )

        controller.configureTransitionStateForTests(visible: true, isTransitioning: false)
        controller.captureRestoreTargetForTests()

        observedTarget = currentTarget
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        await settleQuakeTerminalFocusUpdates()
        controller.animateOut()

        #expect(restoredTargets.isEmpty)
    }

    @Test @MainActor func autoHideOnFocusLossPreservesCurrentFocus() async {
        let initialTarget = makeManagedRestoreTarget(pid: 71, windowId: 710)
        let currentTarget = makeManagedRestoreTarget(pid: 72, windowId: 720)
        var observedTarget = initialTarget
        var restoredTargets: [QuakeTerminalRestoreTarget] = []
        let controller = makeQuakeTerminalTestController(
            autoHide: true,
            captureRestoreTarget: { observedTarget },
            restoreFocusTarget: { restoredTargets.append($0) },
            isWindowFocused: { _ in false }
        )

        controller.configureTransitionStateForTests(visible: true, isTransitioning: false)
        controller.captureRestoreTargetForTests()

        observedTarget = currentTarget
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        await settleQuakeTerminalFocusUpdates()

        #expect(restoredTargets.isEmpty)
        #expect(controller.visible == false)
    }
}

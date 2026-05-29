import Carbon
import Foundation
@testable import Nehir
import Testing

private func makeHotkeyEditorDefaults() -> UserDefaults {
    let suiteName = "HotkeyBindingEditorTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Suite @MainActor struct HotkeyBindingEditorTests {
    @Test func capturingBindingAssignsPreviouslyUnassignedAction() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        let newBinding = KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey))

        settings.clearBinding(for: "move.left")
        let result = HotkeyBindingEditor.capture(newBinding, for: "move.left", settings: settings)

        switch result {
        case .applied:
            break
        case .conflict:
            Issue.record("Expected binding capture to succeed for an unassigned action")
        }

        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding == .chord(newBinding))
    }

    @Test func capturingDuplicateBindingReturnsConflictWithoutMutatingEitherAction() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        let shared = KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey))
        let originalTarget = KeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey))

        settings.updateBinding(for: "move.left", newBinding: shared)
        settings.updateBinding(for: "move.right", newBinding: originalTarget)

        let result = HotkeyBindingEditor.capture(shared, for: "move.right", settings: settings)

        switch result {
        case .applied:
            Issue.record("Expected duplicate capture to produce a conflict")
        case let .conflict(alert):
            #expect(alert.targetActionId == "move.right")
            #expect(alert.newTrigger == .chord(shared))
            #expect(alert.conflictingCommands == ["Move Left"])
        }

        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding == .chord(shared))
        #expect(settings.hotkeyBindings.first { $0.id == "move.right" }?.binding == .chord(originalTarget))
    }

    @Test func applyingConflictResolutionMovesOwnershipToTheNewAction() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        let shared = KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey))
        let originalTarget = KeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey))

        settings.updateBinding(for: "move.left", newBinding: shared)
        settings.updateBinding(for: "move.right", newBinding: originalTarget)

        let result = HotkeyBindingEditor.capture(shared, for: "move.right", settings: settings)
        guard case let .conflict(alert) = result else {
            Issue.record("Expected duplicate capture to produce a conflict alert")
            return
        }

        HotkeyBindingEditor.applyConflictResolution(alert, settings: settings)

        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding == .unassigned)
        #expect(settings.hotkeyBindings.first { $0.id == "move.right" }?.binding == .chord(shared))
    }

    @Test func conflictCaptureLeavesStateUnchangedUntilUserConfirmsReplacement() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        let shared = KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey))
        let originalTarget = KeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey))

        settings.updateBinding(for: "move.left", newBinding: shared)
        settings.updateBinding(for: "move.right", newBinding: originalTarget)

        _ = HotkeyBindingEditor.capture(shared, for: "move.right", settings: settings)

        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding == .chord(shared))
        #expect(settings.hotkeyBindings.first { $0.id == "move.right" }?.binding == .chord(originalTarget))
    }

    @Test func capturingPrefixSequenceReturnsConflictBeforeRuntimeRegistration() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        let short = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let long = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0)),
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: 0))
        ])

        settings.updateTrigger(for: "focus.left", newTrigger: short)
        let result = HotkeyBindingEditor.capture(long, for: "move.left", settings: settings)

        switch result {
        case .applied:
            Issue.record("Expected prefix sequence capture to produce a conflict")
        case let .conflict(alert):
            #expect(alert.targetActionId == "move.left")
            #expect(alert.newTrigger == long)
            #expect(alert.conflictingCommands == ["Focus Left"])
        }

        #expect(settings.hotkeyBindings.first { $0.id == "focus.left" }?.binding == short)
        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding != long)
    }

    @Test func capturingRuntimeEquivalentSequenceReturnsConflictBeforeRegistration() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        settings.modifierTrigger = .system
        let semantic = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let literal = HotkeyTrigger.sequence([
            .chord(KeyBinding(keyCode: UInt32(kVK_Space), modifiers: KeySymbolMapper.hyperModifiers)),
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])

        settings.updateTrigger(for: "focus.left", newTrigger: semantic)
        let result = HotkeyBindingEditor.capture(literal, for: "move.left", settings: settings)

        switch result {
        case .applied:
            Issue.record("Expected runtime-equivalent sequence capture to produce a conflict")
        case let .conflict(alert):
            #expect(alert.targetActionId == "move.left")
            #expect(alert.newTrigger == literal)
            #expect(alert.conflictingCommands == ["Focus Left"])
        }

        #expect(settings.hotkeyBindings.first { $0.id == "focus.left" }?.binding == semantic)
        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding != literal)
    }

    @Test func capturingConflictingSequenceRootReturnsConflictBeforeRegistration() {
        let settings = SettingsStore(defaults: makeHotkeyEditorDefaults())
        settings.modifierTrigger = .system
        let semanticRoot = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let literalRoot = HotkeyTrigger.sequence([
            .chord(KeyBinding(keyCode: UInt32(kVK_Space), modifiers: KeySymbolMapper.hyperModifiers)),
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: 0))
        ])

        settings.updateTrigger(for: "focus.left", newTrigger: semanticRoot)
        let result = HotkeyBindingEditor.capture(literalRoot, for: "move.left", settings: settings)

        switch result {
        case .applied:
            Issue.record("Expected conflicting sequence root capture to produce a conflict")
        case let .conflict(alert):
            #expect(alert.targetActionId == "move.left")
            #expect(alert.newTrigger == literalRoot)
            #expect(alert.conflictingCommands == ["Focus Left"])
        }

        #expect(settings.hotkeyBindings.first { $0.id == "focus.left" }?.binding == semanticRoot)
        #expect(settings.hotkeyBindings.first { $0.id == "move.left" }?.binding != literalRoot)
    }
}

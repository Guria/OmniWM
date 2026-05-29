@testable import Nehir
import Carbon
import CoreGraphics
import Testing

private func makeHotkeyKeyboardEvent(
    keyCode: UInt32,
    flags: CGEventFlags = [],
    autorepeat: Bool = false
) -> CGEvent {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else {
        fatalError("Failed to create hotkey keyboard event")
    }
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
    return event
}

private func makeHotkeyOtherMouseEvent(type: CGEventType, buttonNumber: Int64) -> CGEvent {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let button = CGMouseButton(rawValue: UInt32(buttonNumber)),
          let event = CGEvent(
              mouseEventSource: source,
              mouseType: type,
              mouseCursorPosition: .zero,
              mouseButton: button
          )
    else {
        fatalError("Failed to create hotkey mouse event")
    }
    event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
    return event
}

@Suite struct HotkeyCenterTests {
    @Test func duplicateBindingsAcrossCommandsFailClosedWithDuplicateReason() {
        let shared = KeyBinding(keyCode: 1, modifiers: 2)
        let unique = KeyBinding(keyCode: 3, modifiers: 4)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "move.left", command: .move(.left), binding: shared),
                HotkeyBinding(id: "move.right", command: .move(.right), binding: shared),
                HotkeyBinding(id: "focus.left", command: .focus(.left), binding: unique)
            ]
        )

        #expect(plan.failures == [
            .move(.left): .duplicateBinding,
            .move(.right): .duplicateBinding
        ])
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: unique, command: .focus(.left))
        ])
    }

    @Test func unassignedBindingsAreIgnoredByRegistrationPlan() {
        let unique = KeyBinding(keyCode: 31, modifiers: 41)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "move.left", command: .move(.left), binding: .unassigned),
                HotkeyBinding(id: "move.right", command: .move(.right), binding: unique)
            ]
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: unique, command: .move(.right))
        ])
    }

    @Test func sequenceBindingsShareLeaderRootRegistration() {
        let leader = KeyBinding(keyCode: UInt32(kVK_Space), modifiers: KeySymbolMapper.hyperModifiers)
        let focusLeft = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let focusRight = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: focusLeft),
                HotkeyBinding(id: "focus.right", command: .focus(.right), trigger: focusRight)
            ],
            leaderKey: leader
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: leader, action: .sequencePrefix(leader))
        ])
        #expect(plan.sequenceNodes.first?.children[leader] != nil)
    }

    @Test func duplicateSequencesFailClosed() {
        let trigger = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: trigger),
                HotkeyBinding(id: "move.left", command: .move(.left), trigger: trigger)
            ]
        )

        #expect(plan.failures == [
            .focus(.left): .duplicateSequence,
            .move(.left): .duplicateSequence
        ])
        #expect(plan.registrations.isEmpty)
    }

    @Test func prefixAmbiguousSequencesFailClosed() {
        let short = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let long = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0)),
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: short),
                HotkeyBinding(id: "move.left", command: .move(.left), trigger: long)
            ]
        )

        #expect(plan.failures == [
            .focus(.left): .prefixAmbiguity,
            .move(.left): .prefixAmbiguity
        ])
        #expect(plan.registrations.isEmpty)
    }

    @Test func inputMonitoringDenialFailsOnlySequenceBindings() {
        let direct = KeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey))
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.up", command: .focus(.up), binding: direct),
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            sequenceEventAccessGranted: false
        )

        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: direct, command: .focus(.up))
        ])
    }

    @Test func systemSemanticHyperBindingsRegisterLiteralCompatibilityOnly() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: 0, usesModifier: true)
        let literal = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: KeySymbolMapper.hyperModifiers)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "switchWorkspace.1", command: .switchWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .system
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: literal, command: .switchWorkspace(1))
        ])
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func optionModifierSemanticHyperBindingsRegisterOptionCompatibilityOnly() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: 0, usesModifier: true)
        let literal = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey))
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "switchWorkspace.1", command: .switchWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .modifier(UInt32(optionKey))
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: literal, command: .switchWorkspace(1))
        ])
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func customSemanticHyperBindingsRegisterVirtualTriggerOnly() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: 0, usesModifier: true)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "switchWorkspace.1", command: .switchWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations == [
            HotkeyPlannedRegistration(binding: semantic, command: .switchWorkspace(1))
        ])
    }

    @Test func systemSemanticHyperWithExtraModifiersFailsClosed() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey), usesModifier: true)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "moveToWorkspace.1", command: .moveToWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .system
        )

        #expect(plan.failures == [.moveToWorkspace(1): .unsupportedModifierKeys])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func optionModifierSemanticHyperWithExtraModifiersPreservesExtraModifiers() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey), usesModifier: true)
        let literal = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey | shiftKey))
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "moveToWorkspace.1", command: .moveToWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .modifier(UInt32(optionKey))
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations == [
            HotkeyPlannedRegistration(binding: literal, command: .moveToWorkspace(1))
        ])
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func customSemanticHyperWithExtraModifiersIsVirtualOnly() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey), usesModifier: true)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "moveToWorkspace.1", command: .moveToWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations == [
            HotkeyPlannedRegistration(binding: semantic, command: .moveToWorkspace(1))
        ])
    }

    @Test func customModifierHyperWithSameExtraModifierFailsClosed() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey), usesModifier: true)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "moveToWorkspace.1", command: .moveToWorkspace(1), binding: semantic)
            ],
            modifierTrigger: .key(UInt32(kVK_Shift))
        )

        #expect(plan.failures == [.moveToWorkspace(1): .unsupportedModifierKeys])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func customModifierHyperSequenceRootWithSameExtraModifierFailsClosed() {
        let semanticLeader = KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey), usesModifier: true)
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_Space), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_Shift)),
            leaderKey: semanticLeader
        )

        #expect(plan.failures == [.focus(.left): .unsupportedModifierKeys])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func systemSequenceWithModifiedSemanticHyperStepFailsClosed() {
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(shiftKey), usesModifier: true))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ]
        )

        #expect(plan.failures == [.focus(.left): .unsupportedSequenceModifierStep])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func customSequenceWithSemanticHyperStepFailsClosed() {
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0, usesModifier: true))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )

        #expect(plan.failures == [.focus(.left): .unsupportedSequenceModifierStep])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func semanticHyperConflictsWithLiteralAllModifierCompatibilityChord() {
        let semantic = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: 0, usesModifier: true)
        let literal = KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: KeySymbolMapper.hyperModifiers)
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "switchWorkspace.1", command: .switchWorkspace(1), binding: semantic),
                HotkeyBinding(id: "focus.left", command: .focus(.left), binding: literal)
            ],
            modifierTrigger: .system
        )

        #expect(plan.failures == [
            .switchWorkspace(1): .duplicateBinding,
            .focus(.left): .duplicateBinding
        ])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func literalAllModifierChordConflictsWithSemanticLeaderRoot() {
        let literalLeader = KeyBinding(keyCode: UInt32(kVK_Space), modifiers: KeySymbolMapper.hyperModifiers)
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])
        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "openCommandPalette", command: .openCommandPalette, binding: literalLeader),
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .system
        )

        #expect(plan.failures == [
            .openCommandPalette: .sequenceRootConflict,
            .focus(.left): .sequenceRootConflict
        ])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func rawLeaderMatchingCustomHyperTriggerFailsSequenceBindings() {
        let rawCapsLeader = KeyBinding(keyCode: UInt32(kVK_CapsLock), modifiers: 0)
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
        ])

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock)),
            leaderKey: rawCapsLeader
        )

        #expect(plan.failures == [.focus(.left): .modifierLeaderConflict])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func semanticHyperLeaderWithCustomHyperTriggerIsAllowed() {
        let semanticLeader = KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true)
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_Space), modifiers: 0))
        ])

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock)),
            leaderKey: semanticLeader
        )

        #expect(plan.failures.isEmpty)
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations == [
            HotkeyPlannedRegistration(binding: semanticLeader, action: .sequencePrefix(semanticLeader))
        ])
    }

    @Test func semanticHyperLeaderMatchingCustomHyperTriggerFailsSequenceBindings() {
        let semanticLeader = KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true)
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_Space), modifiers: 0))
        ])

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_ANSI_S)),
            leaderKey: semanticLeader
        )

        #expect(plan.failures == [.focus(.left): .modifierLeaderConflict])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func directBindingMatchingCustomHyperTriggerFailsRegistration() {
        let binding = KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey), usesModifier: true)

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), binding: binding)
            ],
            modifierTrigger: .key(UInt32(kVK_ANSI_S))
        )

        #expect(plan.failures == [.focus(.left): .modifierLeaderConflict])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func directBindingMatchingOptionModifierFamilyFailsRegistration() {
        let binding = KeyBinding(keyCode: UInt32(kVK_RightOption), modifiers: 0)

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), binding: binding)
            ],
            modifierTrigger: .modifier(UInt32(optionKey))
        )

        #expect(plan.failures == [.focus(.left): .modifierLeaderConflict])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func sequenceStepMatchingCustomHyperTriggerFailsRegistration() {
        let sequence = HotkeyTrigger.sequence([
            .leader,
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0))
        ])

        let plan = HotkeyCenter.registrationPlan(
            for: [
                HotkeyBinding(id: "focus.left", command: .focus(.left), trigger: sequence)
            ],
            modifierTrigger: .key(UInt32(kVK_ANSI_S))
        )

        #expect(plan.failures == [.focus(.left): .modifierLeaderConflict])
        #expect(plan.registrations.isEmpty)
        #expect(plan.virtualModifierRegistrations.isEmpty)
    }

    @Test func capsLockFlagsChangedUsesFlagStateInsteadOfToggling() {
        var state = VirtualModifierEventState()
        let trigger = ModifierKeyTrigger.key(UInt32(kVK_CapsLock))

        let firstPressHandled = state.handleTriggerFlagsChanged(
            keyCode: UInt32(kVK_CapsLock),
            flags: .maskAlphaShift,
            trigger: trigger
        )
        #expect(firstPressHandled)
        #expect(state.isActive)

        let repeatedActiveFlagsHandled = state.handleTriggerFlagsChanged(
            keyCode: UInt32(kVK_CapsLock),
            flags: .maskAlphaShift,
            trigger: trigger
        )
        #expect(repeatedActiveFlagsHandled)
        #expect(state.isActive)

        let releaseHandled = state.handleTriggerFlagsChanged(
            keyCode: UInt32(kVK_CapsLock),
            flags: [],
            trigger: trigger
        )
        #expect(releaseHandled)
        #expect(!state.isActive)
    }

    @Test func modifierHyperFlagsChangedUsesPhysicalKeyIdentityWhenAggregateFlagStaysActive() {
        var state = VirtualModifierEventState()
        let trigger = ModifierKeyTrigger.key(UInt32(kVK_Shift))

        let pressHandled = state.handleTriggerFlagsChanged(
            keyCode: UInt32(kVK_Shift),
            flags: .maskShift,
            trigger: trigger
        )
        #expect(pressHandled)
        #expect(state.isActive)

        let releaseHandled = state.handleTriggerFlagsChanged(
            keyCode: UInt32(kVK_Shift),
            flags: .maskShift,
            trigger: trigger
        )
        #expect(releaseHandled)
        #expect(!state.isActive)
    }

    @Test func virtualHyperPassesThroughUnregisteredAutorepeatWithoutConsuming() {
        var state = VirtualModifierEventState(isActive: true)
        let trigger = ModifierKeyTrigger.key(UInt32(kVK_CapsLock))
        let initialDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_Delete),
            isAutorepeat: false,
            trigger: trigger,
            sequenceIsActive: false,
            action: nil
        )
        let repeatDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_Delete),
            isAutorepeat: true,
            trigger: trigger,
            sequenceIsActive: false,
            action: nil
        )

        #expect(initialDecision == .passThrough)
        #expect(repeatDecision == .passThrough)
        #expect(!state.consumedKeyCodes.contains(UInt32(kVK_Delete)))
    }

    @Test func registeredVirtualHyperSuppressesInitialAndRepeatKeyDowns() {
        var state = VirtualModifierEventState(isActive: true)
        let trigger = ModifierKeyTrigger.key(UInt32(kVK_CapsLock))
        let action = HotkeyRegistrationAction.command(.focus(.left))

        let initialDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: false,
            trigger: trigger,
            sequenceIsActive: false,
            action: action
        )
        let repeatDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: true,
            trigger: trigger,
            sequenceIsActive: false,
            action: action
        )

        #expect(initialDecision == .dispatch(action))
        #expect(repeatDecision == .suppress)
        #expect(state.consumedKeyCodes.contains(UInt32(kVK_ANSI_S)))
    }

    @Test func mouseButtonVirtualHyperDispatchesAndSuppressesRegisteredKey() {
        var state = VirtualModifierEventState()
        let trigger = ModifierKeyTrigger.mouseButton(4)
        let action = HotkeyRegistrationAction.command(.focus(.left))

        let triggerDownHandled = state.handleTriggerMouseDown(4, trigger: trigger)
        #expect(triggerDownHandled)
        #expect(state.isActive)

        let initialDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: false,
            trigger: trigger,
            sequenceIsActive: false,
            action: action
        )
        let repeatDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: true,
            trigger: trigger,
            sequenceIsActive: false,
            action: action
        )

        #expect(initialDecision == .dispatch(action))
        #expect(repeatDecision == .suppress)
        #expect(state.consumedKeyCodes.contains(UInt32(kVK_ANSI_S)))
        let keyUpHandled = state.handleTriggerKeyUp(UInt32(kVK_ANSI_S), trigger: trigger)
        #expect(keyUpHandled)
        #expect(!state.consumedKeyCodes.contains(UInt32(kVK_ANSI_S)))
        let triggerUpHandled = state.handleTriggerMouseUp(4, trigger: trigger)
        #expect(triggerUpHandled)
        #expect(!state.isActive)
    }

    @Test func mouseButtonVirtualHyperPassesThroughUnregisteredKey() {
        var state = VirtualModifierEventState()
        let trigger = ModifierKeyTrigger.mouseButton(4)

        let triggerDownHandled = state.handleTriggerMouseDown(4, trigger: trigger)
        #expect(triggerDownHandled)
        let initialDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: false,
            trigger: trigger,
            sequenceIsActive: false,
            action: nil
        )
        let repeatDecision = state.handleKeyDown(
            keyCode: UInt32(kVK_ANSI_S),
            isAutorepeat: true,
            trigger: trigger,
            sequenceIsActive: false,
            action: nil
        )

        #expect(initialDecision == .passThrough)
        #expect(repeatDecision == .passThrough)
        #expect(!state.consumedKeyCodes.contains(UInt32(kVK_ANSI_S)))
    }

    @Test @MainActor func virtualHyperKeyDownPathStripsTriggerModifierAndSuppressesRepeat() {
        let center = HotkeyCenter()
        var commands: [HotkeyCommand] = []
        let action = HotkeyRegistrationAction.command(.focus(.left))
        center.onCommand = { commands.append($0) }
        center.prepareVirtualHyperForTesting(
            modifierTrigger: .key(UInt32(kVK_Shift)),
            registrations: [
                KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true): action
            ],
            isActive: true
        )

        let initialEvent = makeHotkeyKeyboardEvent(keyCode: UInt32(kVK_ANSI_S), flags: .maskShift)
        let initialResult = center.handleVirtualHyperEventForTesting(type: .keyDown, event: initialEvent)
        #expect(initialResult == nil)
        #expect(commands.isEmpty)
        center.drainPendingSequenceCommandsForTesting()
        #expect(commands == [.focus(.left)])

        let repeatEvent = makeHotkeyKeyboardEvent(
            keyCode: UInt32(kVK_ANSI_S),
            flags: .maskShift,
            autorepeat: true
        )
        let repeatResult = center.handleVirtualHyperEventForTesting(type: .keyDown, event: repeatEvent)
        #expect(repeatResult == nil)
        center.drainPendingSequenceCommandsForTesting()
        #expect(commands == [.focus(.left)])
    }

    @Test @MainActor func virtualHyperKeyDownPathPassesThroughDuringActiveSequence() {
        let center = HotkeyCenter()
        var commands: [HotkeyCommand] = []
        let action = HotkeyRegistrationAction.command(.focus(.left))
        center.onCommand = { commands.append($0) }
        center.prepareVirtualHyperForTesting(
            modifierTrigger: .key(UInt32(kVK_Shift)),
            registrations: [
                KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true): action
            ],
            isActive: true,
            sequenceIsActive: true
        )

        let event = makeHotkeyKeyboardEvent(keyCode: UInt32(kVK_ANSI_S), flags: .maskShift)
        let result = center.handleVirtualHyperEventForTesting(type: .keyDown, event: event)
        #expect(result != nil)
        center.drainPendingSequenceCommandsForTesting()
        #expect(commands.isEmpty)
    }

    @Test @MainActor func mouseButtonVirtualHyperCenterPathDispatchesAndSuppressesRegisteredKey() {
        let center = HotkeyCenter()
        var commands: [HotkeyCommand] = []
        let action = HotkeyRegistrationAction.command(.focus(.left))
        center.onCommand = { commands.append($0) }
        center.prepareVirtualHyperForTesting(
            modifierTrigger: .mouseButton(4),
            registrations: [
                KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true): action
            ]
        )

        let triggerDown = makeHotkeyOtherMouseEvent(type: .otherMouseDown, buttonNumber: 4)
        #expect(center.handleVirtualHyperEventForTesting(type: .otherMouseDown, event: triggerDown) == nil)

        let initialEvent = makeHotkeyKeyboardEvent(keyCode: UInt32(kVK_ANSI_S))
        #expect(center.handleVirtualHyperEventForTesting(type: .keyDown, event: initialEvent) == nil)
        center.drainPendingSequenceCommandsForTesting()
        #expect(commands == [.focus(.left)])

        let repeatEvent = makeHotkeyKeyboardEvent(keyCode: UInt32(kVK_ANSI_S), autorepeat: true)
        #expect(center.handleVirtualHyperEventForTesting(type: .keyDown, event: repeatEvent) == nil)
        center.drainPendingSequenceCommandsForTesting()
        #expect(commands == [.focus(.left)])

        let triggerUp = makeHotkeyOtherMouseEvent(type: .otherMouseUp, buttonNumber: 4)
        #expect(center.handleVirtualHyperEventForTesting(type: .otherMouseUp, event: triggerUp) == nil)
    }

    @Test @MainActor func sequenceTapUnavailableFailsSequenceCommands() {
        let center = HotkeyCenter()
        defer { center.stop() }
        center.sequenceEventAccessProvider = { true }
        center.sequenceTapSetupOverride = { false }
        center.updateBindings([
            HotkeyBinding(
                id: "focus.left",
                command: .focus(.left),
                trigger: .sequence([
                    .leader,
                    .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
                ])
            )
        ])

        center.start()

        #expect(center.registrationFailures == [.focus(.left): .eventTapUnavailable])
    }

    @Test @MainActor func sequenceTapUnavailableSkipsVirtualHyperSequencePrefixSetup() {
        let center = HotkeyCenter()
        defer { center.stop() }
        var virtualModifierTapSetupCalls = 0
        let semanticLeader = KeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, usesModifier: true)
        center.sequenceEventAccessProvider = { true }
        center.sequenceTapSetupOverride = { false }
        center.virtualModifierTapSetupOverride = {
            virtualModifierTapSetupCalls += 1
            return true
        }
        center.updateBindings(
            [
                HotkeyBinding(
                    id: "focus.left",
                    command: .focus(.left),
                    trigger: .sequence([
                        .leader,
                        .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0))
                    ])
                )
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock)),
            leaderKey: semanticLeader
        )

        center.start()

        #expect(center.registrationFailures == [.focus(.left): .eventTapUnavailable])
        #expect(virtualModifierTapSetupCalls == 0)
    }

    @Test @MainActor func virtualModifierTapUnavailableFailsVirtualHyperCommands() {
        let center = HotkeyCenter()
        defer { center.stop() }
        center.sequenceEventAccessProvider = { true }
        center.virtualModifierTapSetupOverride = { false }
        center.updateBindings(
            [
                HotkeyBinding(
                    id: "switchWorkspace.1",
                    command: .switchWorkspace(1),
                    binding: KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey), usesModifier: true)
                )
            ],
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )

        center.start()

        #expect(center.registrationFailures == [.switchWorkspace(1): .eventTapUnavailable])
    }

    @Test @MainActor func unchangedRuntimeConfigurationSkipsHotkeyRebuildUnlessForced() {
        let center = HotkeyCenter()
        defer { center.stop() }
        var virtualModifierTapSetupCalls = 0
        let bindings = [
            HotkeyBinding(
                id: "switchWorkspace.1",
                command: .switchWorkspace(1),
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: 0, usesModifier: true)
            )
        ]
        center.virtualModifierTapSetupOverride = {
            virtualModifierTapSetupCalls += 1
            return true
        }
        center.updateBindings(
            bindings,
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )

        center.start()
        #expect(virtualModifierTapSetupCalls == 1)

        center.updateBindings(
            bindings,
            modifierTrigger: .key(UInt32(kVK_CapsLock))
        )
        #expect(virtualModifierTapSetupCalls == 1)

        center.updateBindings(
            bindings,
            modifierTrigger: .key(UInt32(kVK_CapsLock)),
            force: true
        )
        #expect(virtualModifierTapSetupCalls == 2)
    }
}

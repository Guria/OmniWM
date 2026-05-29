import Carbon
import SwiftUI

enum HotkeyCaptureResult {
    case applied
    case conflict(ConflictAlert)
}

@MainActor enum HotkeyBindingEditor {
    static func capture(
        _ newBinding: KeyBinding,
        for actionId: String,
        settings: SettingsStore
    ) -> HotkeyCaptureResult {
        capture(newBinding.isUnassigned ? .unassigned : .chord(newBinding), for: actionId, settings: settings)
    }

    static func capture(
        _ newTrigger: HotkeyTrigger,
        for actionId: String,
        settings: SettingsStore
    ) -> HotkeyCaptureResult {
        let conflicts = settings.findConflicts(for: newTrigger, excluding: actionId)
        guard conflicts.isEmpty else {
            return .conflict(
                ConflictAlert(
                    targetActionId: actionId,
                    newTrigger: newTrigger,
                    conflictingCommands: conflicts.map(\.command.displayName)
                )
            )
        }

        settings.updateTrigger(for: actionId, newTrigger: newTrigger)
        return .applied
    }

    static func applyConflictResolution(_ alert: ConflictAlert, settings: SettingsStore) {
        let conflicts = settings.findConflicts(for: alert.newTrigger, excluding: alert.targetActionId)
        for conflict in conflicts {
            settings.clearBinding(for: conflict.id)
        }
        settings.updateTrigger(for: alert.targetActionId, newTrigger: alert.newTrigger)
    }
}

private enum HotkeyRecordingTarget: Equatable {
    case chord(String)
    case sequenceStep(String)
    case hyperTrigger
    case leader
}

enum HotkeyInputMonitoringStatus: Equatable {
    case granted
    case denied

    init(granted: Bool) {
        self = granted ? .granted : .denied
    }

    var displayText: String {
        switch self {
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        }
    }
}

enum HotkeySettingsDisplayModel {
    static func showsSequenceControls(
        showsAdvancedHotkeys: Bool,
        isRecordingOrDrafting: Bool,
        bindings: [HotkeyBinding]
    ) -> Bool {
        showsAdvancedHotkeys || isRecordingOrDrafting || bindings.contains { binding in
            guard case .sequence = binding.binding else { return false }
            return true
        }
    }

    static func isVisible(bindingId: String, showsAdvancedHotkeys: Bool) -> Bool {
        switch ActionCatalog.visibility(for: bindingId) ?? .normal {
        case .normal:
            true
        case .advanced:
            showsAdvancedHotkeys
        case .hidden:
            false
        }
    }

    static func matchesSearch(_ query: String, binding: HotkeyBinding) -> Bool {
        let normalizedQuery = ActionCatalog.normalizedSearchTerm(query)
        guard !normalizedQuery.isEmpty else { return true }
        let actionTerms = ActionCatalog.spec(for: binding.id)?.searchTerms ?? [
            binding.command.displayName,
            binding.command.layoutCompatibility.rawValue
        ]
        let searchTerms = actionTerms + [
            displayString(for: binding.binding),
            humanReadableString(for: binding.binding)
        ]
        return searchTerms.contains {
            ActionCatalog.normalizedSearchTerm($0).contains(normalizedQuery)
        }
    }

    static func displayString(for binding: KeyBinding) -> String {
        if binding.isUnassigned {
            return "Unassigned"
        }
        let prefix = binding.usesHyper ? "Nehir+" : ""
        return prefix + KeySymbolMapper.displayString(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    static func displayString(for step: HotkeySequenceStep) -> String {
        switch step {
        case .leader:
            return "Leader"
        case let .chord(binding):
            return displayString(for: binding)
        }
    }

    static func displayString(for trigger: HotkeyTrigger) -> String {
        switch trigger {
        case .unassigned:
            return "Unassigned"
        case let .chord(binding):
            return displayString(for: binding)
        case let .sequence(steps):
            return steps.map { displayString(for: $0) }.joined(separator: ", ")
        }
    }

    static func humanReadableString(for binding: KeyBinding) -> String {
        if binding.isUnassigned {
            return "Unassigned"
        }
        let base = KeySymbolMapper.humanReadableString(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        )
        return binding.usesHyper ? "Nehir modifier+\(base)" : base
    }

    static func humanReadableString(for step: HotkeySequenceStep) -> String {
        switch step {
        case .leader:
            return "Leader"
        case let .chord(binding):
            return humanReadableString(for: binding)
        }
    }

    static func humanReadableString(for trigger: HotkeyTrigger) -> String {
        switch trigger {
        case .unassigned:
            return "Unassigned"
        case let .chord(binding):
            return humanReadableString(for: binding)
        case let .sequence(steps):
            return steps.map { humanReadableString(for: $0) }.joined(separator: ", ")
        }
    }

    static func inputMonitoringStatus(
        preflightGranted: Bool,
        requestIfNeeded: Bool,
        requestGranted: Bool
    ) -> HotkeyInputMonitoringStatus {
        HotkeyInputMonitoringStatus(granted: preflightGranted || (requestIfNeeded && requestGranted))
    }
}

struct HotkeySettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @State private var recordingTarget: HotkeyRecordingTarget?
    @State private var sequenceDraftActionId: String?
    @State private var sequenceDraftSteps: [HotkeySequenceStep] = []
    @State private var conflictAlert: ConflictAlert?
    @State private var leaderConflictAlert: LeaderConflictAlert?
    @State private var noticeAlert: HotkeyNoticeAlert?
    @State private var searchText: String = ""
    @State private var showsAdvancedHotkeys = false
    @State private var confirmsResetToDefaults = false
    @State private var inputMonitoringStatus = HotkeyInputMonitoringStatus(
        granted: HotkeyCenter.sequenceEventAccessGranted()
    )

    var body: some View {
        SettingsPage(
            subtitle: "Search commands, edit shortcuts, and review registration problems without leaving the settings window."
        ) {
            Section("Controls") {
                LabeledContent("Advanced") {
                    Toggle("Show Advanced", isOn: $showsAdvancedHotkeys)
                        .toggleStyle(.switch)
                }

                if showsSequenceControls {
                    LabeledContent("Leader Key") {
                        HStack(spacing: 8) {
                            if recordingTarget == .leader {
                                KeyRecorderView(
                                    accessibilityLabel: "Recording leader key",
                                    hyperTrigger: settings.hyperTrigger,
                                    onCapture: handleLeaderCaptured,
                                    onCancel: cancelRecording
                                )
                                .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                            } else {
                                Button {
                                    startLeaderRecording()
                                } label: {
                                    Text(HotkeySettingsDisplayModel.displayString(for: settings.effectiveLeaderKey))
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 112, alignment: .center)
                                }
                                .buttonStyle(.bordered)
                                .help("Change leader key. Current leader: \(HotkeySettingsDisplayModel.humanReadableString(for: settings.effectiveLeaderKey))")
                                .accessibilityLabel("Change leader key")
                                .accessibilityValue(HotkeySettingsDisplayModel.humanReadableString(for: settings.effectiveLeaderKey))
                            }
                        }
                    }

                    LabeledContent("Sequence Timeout") {
                        Stepper(value: $settings.sequenceTimeoutMilliseconds, in: 100 ... 3000, step: 100) {
                            Text("\(settings.sequenceTimeoutMilliseconds) ms")
                                .monospacedDigit()
                        }
                        .onChange(of: settings.sequenceTimeoutMilliseconds) { _, _ in
                            controller.updateHotkeyBindings(settings.hotkeyBindings)
                        }
                    }
                }

                LabeledContent("Nehir Modifier") {
                    HStack(spacing: 8) {
                        if recordingTarget == .hyperTrigger {
                            HyperTriggerRecorderView(
                                accessibilityLabel: "Recording Nehir modifier",
                                onCapture: handleHyperTriggerCaptured,
                                onCancel: cancelRecording
                            )
                            .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                        } else {
                            Button {
                                startHyperTriggerRecording()
                            } label: {
                                Text(settings.hyperTrigger.displayString)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(minWidth: 112, alignment: .center)
                            }
                            .buttonStyle(.bordered)
                            .help("Change Nehir modifier. Current Nehir modifier: \(settings.hyperTrigger.humanReadableString)")
                            .accessibilityLabel("Change Nehir modifier")
                            .accessibilityValue(settings.hyperTrigger.humanReadableString)
                        }
                    }
                }

                LabeledContent("Input Monitoring") {
                    HStack(spacing: 10) {
                        Text(inputMonitoringStatus.displayText)
                            .foregroundStyle(inputMonitoringStatus == .granted ? Color.secondary : Color.orange)
                        Button("Request Permission") {
                            refreshInputMonitoringStatus(requestIfNeeded: true)
                        }
                    }
                }

                LabeledContent("Defaults") {
                    Button("Reset to Defaults", role: .destructive) {
                        confirmsResetToDefaults = true
                    }
                }
            }

            Section("Shortcuts") {
                LabeledContent("Search") {
                    HStack(spacing: 8) {
                        TextField("Command, shortcut, or scope", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search hotkeys")

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Label("Clear search", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear search")
                            .accessibilityLabel("Clear hotkey search")
                        }
                    }
                }

                if !hasSearchMatches {
                    Text("No matching hotkeys.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(HotkeyCategory.allCases, id: \.self) { category in
                let actions = actionsForCategory(category)
                if !actions.isEmpty {
                    Section(category.rawValue) {
                        ForEach(actions) { binding in
                            HotkeyBindingRow(
                                binding: binding,
                                recordingTarget: $recordingTarget,
                                sequenceDraftActionId: sequenceDraftActionId,
                                sequenceDraftSteps: sequenceDraftSteps,
                                hyperTrigger: settings.hyperTrigger,
                                failureReason: controller.hotkeyRegistrationFailures[binding.command],
                                onStartChordRecording: startChordRecording,
                                onStartSequenceRecording: startSequenceRecording,
                                onChordCaptured: handleChordCaptured,
                                onSequenceStepCaptured: handleSequenceStepCaptured,
                                onAddSequenceStep: addSequenceStep,
                                onApplySequence: applySequenceDraft,
                                onCancelSequence: cancelRecording,
                                onClearBinding: clearBinding,
                                onResetBindings: resetBindings
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            inputMonitoringStatus = HotkeyInputMonitoringStatus(
                granted: HotkeyCenter.sequenceEventAccessGranted()
            )
        }
        .onChange(of: recordingTarget) { _, _ in
            syncHotkeyRecordingState()
        }
        .onDisappear {
            guard isRecordingOrDrafting else { return }
            cancelRecording()
            controller.setHotkeysEnabled(settings.hotkeysEnabled)
        }
        .alert(item: $conflictAlert) { alert in
            Alert(
                title: Text("Hotkey Conflict"),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Replace")) {
                    HotkeyBindingEditor.applyConflictResolution(alert, settings: settings)
                    controller.updateHotkeyBindings(settings.hotkeyBindings)
                    cancelRecording()
                },
                secondaryButton: .cancel {
                    cancelRecording()
                }
            )
        }
        .alert(item: $leaderConflictAlert) { alert in
            Alert(
                title: Text("Leader Key Conflict"),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Replace")) {
                    for actionId in alert.conflictingActionIds {
                        settings.clearBinding(for: actionId)
                    }
                    settings.leaderKey = alert.newLeaderKey
                    controller.updateHotkeyBindings(settings.hotkeyBindings)
                    cancelRecording()
                },
                secondaryButton: .cancel {
                    cancelRecording()
                }
            )
        }
        .alert(item: $noticeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    cancelRecording()
                }
            )
        }
        .confirmationDialog("Reset all hotkeys?", isPresented: $confirmsResetToDefaults) {
            Button("Reset Hotkeys", role: .destructive) {
                settings.resetHotkeysToDefaults()
                controller.updateHotkeyBindings(settings.hotkeyBindings)
                cancelRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All hotkey bindings will be restored to Nehir defaults.")
        }
    }

    private var hasSearchMatches: Bool {
        visibleHotkeyBindings.contains {
            HotkeySettingsDisplayModel.matchesSearch(searchText, binding: $0)
        }
    }

    private var visibleHotkeyBindings: [HotkeyBinding] {
        settings.hotkeyBindings.filter(isVisible)
    }

    private var showsSequenceControls: Bool {
        HotkeySettingsDisplayModel.showsSequenceControls(
            showsAdvancedHotkeys: showsAdvancedHotkeys,
            isRecordingOrDrafting: isRecordingOrDrafting,
            bindings: settings.hotkeyBindings
        )
    }

    private func actionsForCategory(_ category: HotkeyCategory) -> [HotkeyBinding] {
        visibleHotkeyBindings.filter { binding in
            binding.category == category && HotkeySettingsDisplayModel.matchesSearch(searchText, binding: binding)
        }
    }

    private func isVisible(_ binding: HotkeyBinding) -> Bool {
        HotkeySettingsDisplayModel.isVisible(
            bindingId: binding.id,
            showsAdvancedHotkeys: showsAdvancedHotkeys
        )
    }

    private var isRecordingOrDrafting: Bool {
        recordingTarget != nil || sequenceDraftActionId != nil
    }

    private func startChordRecording(for actionId: String) {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .chord(actionId)
    }

    private func startLeaderRecording() {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .leader
    }

    private func startHyperTriggerRecording() {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .hyperTrigger
    }

    private func startSequenceRecording(for actionId: String) {
        sequenceDraftActionId = actionId
        sequenceDraftSteps = [.leader]
        recordingTarget = .sequenceStep(actionId)
    }

    private func addSequenceStep(actionId: String) {
        recordingTarget = .sequenceStep(actionId)
    }

    private func handleChordCaptured(actionId: String, newBinding: KeyBinding) {
        handleTriggerCaptured(actionId: actionId, newTrigger: newBinding.isUnassigned ? .unassigned : .chord(newBinding))
    }

    private func handleSequenceStepCaptured(actionId: String, newBinding: KeyBinding) {
        guard sequenceDraftActionId == actionId else { return }
        sequenceDraftSteps.append(.chord(newBinding))
        recordingTarget = nil
        syncHotkeyRecordingState()
    }

    private func applySequenceDraft(actionId: String) {
        guard sequenceDraftActionId == actionId, sequenceDraftSteps.count >= 2 else { return }
        handleTriggerCaptured(actionId: actionId, newTrigger: .sequence(sequenceDraftSteps))
    }

    private func handleLeaderCaptured(_ newBinding: KeyBinding) {
        let resolvedLeader = newBinding.isUnassigned ? KeyBinding.defaultLeader : newBinding
        if settings.leaderKey(resolvedLeader, conflictsWith: settings.hyperTrigger) {
            noticeAlert = HotkeyNoticeAlert(
                title: "Leader Key Conflict",
                message: "The leader key cannot use the same physical key as the configured Nehir modifier. Use an Nehir modifier chord with a different final key, or choose a different Nehir modifier."
            )
            cancelRecording()
            return
        }
        let conflicts = settings.findLeaderRootConflicts(for: newBinding)
        guard conflicts.isEmpty else {
            leaderConflictAlert = LeaderConflictAlert(
                newLeaderKey: resolvedLeader,
                conflictingActionIds: conflicts.map(\.id),
                conflictingCommands: conflicts.map(\.command.displayName)
            )
            cancelRecording()
            return
        }
        settings.leaderKey = newBinding
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func handleHyperTriggerCaptured(_ newTrigger: HyperKeyTrigger) {
        if settings.leaderKey(settings.effectiveLeaderKey, conflictsWith: newTrigger) {
            noticeAlert = HotkeyNoticeAlert(
                title: "Nehir Modifier Conflict",
                message: "The Nehir modifier cannot use the same physical key as the leader key. Keep the leader on a different Nehir modifier chord, or choose a different Nehir modifier."
            )
            cancelRecording()
            return
        }
        settings.hyperTrigger = newTrigger
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func handleTriggerCaptured(actionId: String, newTrigger: HotkeyTrigger) {
        switch HotkeyBindingEditor.capture(newTrigger, for: actionId, settings: settings) {
        case .applied:
            controller.updateHotkeyBindings(settings.hotkeyBindings)
            cancelRecording()
        case let .conflict(alert):
            conflictAlert = alert
            cancelRecording()
        }
    }

    private func clearBinding(actionId: String) {
        settings.clearBinding(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func resetBindings(actionId: String) {
        settings.resetBindings(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func cancelRecording() {
        recordingTarget = nil
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        syncHotkeyRecordingState()
    }

    @discardableResult
    private func refreshInputMonitoringStatus(requestIfNeeded: Bool) -> Bool {
        let preflightGranted = HotkeyCenter.sequenceEventAccessGranted()
        let requestGranted: Bool
        if preflightGranted || !requestIfNeeded {
            requestGranted = false
        } else {
            requestGranted = HotkeyCenter.requestSequenceEventAccess()
        }
        let status = HotkeySettingsDisplayModel.inputMonitoringStatus(
            preflightGranted: preflightGranted,
            requestIfNeeded: requestIfNeeded,
            requestGranted: requestGranted
        )
        inputMonitoringStatus = status
        controller.updateHotkeyBindings(settings.hotkeyBindings, force: true)
        return status == .granted
    }

    private func syncHotkeyRecordingState() {
        controller.setHotkeysEnabled(isRecordingOrDrafting ? false : settings.hotkeysEnabled)
    }
}

struct ConflictAlert: Identifiable {
    let targetActionId: String
    let newTrigger: HotkeyTrigger
    let conflictingCommands: [String]

    var id: String {
        [
            targetActionId,
            newTrigger.humanReadableString,
            conflictingCommands.joined(separator: "|")
        ].joined(separator: ":")
    }

    var message: String {
        if conflictingCommands.count == 1 {
            return "This key combination is already used by \"\(conflictingCommands[0])\". Do you want to replace it?"
        } else {
            let commandList = conflictingCommands.joined(separator: ", ")
            return "This key combination is used by: \(commandList). Do you want to replace all?"
        }
    }
}

struct LeaderConflictAlert: Identifiable {
    let newLeaderKey: KeyBinding
    let conflictingActionIds: [String]
    let conflictingCommands: [String]

    var id: String {
        [
            newLeaderKey.humanReadableString,
            conflictingActionIds.joined(separator: "|")
        ].joined(separator: ":")
    }

    var message: String {
        if conflictingCommands.count == 1 {
            return "This leader key is already used by \"\(conflictingCommands[0])\". Do you want to replace it?"
        } else {
            return "This leader key is used by: \(conflictingCommands.joined(separator: ", ")). Do you want to replace all?"
        }
    }
}

struct HotkeyNoticeAlert: Identifiable {
    let title: String
    let message: String

    var id: String {
        title + ":" + message
    }
}

private struct HotkeyBindingRow: View {
    let binding: HotkeyBinding
    @Binding var recordingTarget: HotkeyRecordingTarget?
    let sequenceDraftActionId: String?
    let sequenceDraftSteps: [HotkeySequenceStep]
    let hyperTrigger: HyperKeyTrigger
    let failureReason: HotkeyRegistrationFailureReason?
    let onStartChordRecording: (String) -> Void
    let onStartSequenceRecording: (String) -> Void
    let onChordCaptured: (String, KeyBinding) -> Void
    let onSequenceStepCaptured: (String, KeyBinding) -> Void
    let onAddSequenceStep: (String) -> Void
    let onApplySequence: (String) -> Void
    let onCancelSequence: () -> Void
    let onClearBinding: (String) -> Void
    let onResetBindings: (String) -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let failureReason {
                    Label("Registration issue", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(failureMessage(for: failureReason))
                        .accessibilityLabel("Registration issue")
                        .accessibilityValue(failureMessage(for: failureReason))
                }

                HotkeyBindingControl(
                    binding: binding.binding,
                    commandName: binding.command.displayName,
                    isRecordingChord: recordingTarget == .chord(binding.id),
                    isRecordingSequenceStep: recordingTarget == .sequenceStep(binding.id),
                    sequenceDraftSteps: sequenceDraftActionId == binding.id ? sequenceDraftSteps : nil,
                    hyperTrigger: hyperTrigger,
                    onStartChordRecording: {
                        onStartChordRecording(binding.id)
                    },
                    onStartSequenceRecording: {
                        onStartSequenceRecording(binding.id)
                    },
                    onCaptured: { newBinding in
                        onChordCaptured(binding.id, newBinding)
                    },
                    onSequenceStepCaptured: { newBinding in
                        onSequenceStepCaptured(binding.id, newBinding)
                    },
                    onAddSequenceStep: {
                        onAddSequenceStep(binding.id)
                    },
                    onApplySequence: {
                        onApplySequence(binding.id)
                    },
                    onCancel: {
                        onCancelSequence()
                    },
                    onRemove: {
                        onClearBinding(binding.id)
                    }
                )

                ResetIconButton(title: "Reset \(binding.command.displayName) to default") {
                    recordingTarget = nil
                    onResetBindings(binding.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(binding.command.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    if let failureReason {
                        Text(failureMessage(for: failureReason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [
            "Shortcut \(HotkeySettingsDisplayModel.humanReadableString(for: binding.binding))",
            "Scope \(binding.command.layoutCompatibility.rawValue)"
        ]
        if let failureReason {
            parts.append(failureMessage(for: failureReason))
        }
        return parts.joined(separator: ", ")
    }

    private func failureMessage(for reason: HotkeyRegistrationFailureReason) -> String {
        switch reason {
        case .duplicateBinding:
            return "Failed to register: this key combination is already assigned to another Nehir command"
        case .duplicateSequence:
            return "Failed to register: this sequence is already assigned to another Nehir command"
        case .prefixAmbiguity:
            return "Failed to register: this sequence is a prefix of another Nehir sequence"
        case .invalidSequenceRoot:
            return "Failed to register: sequence roots must use the leader key, modifiers, or a special key"
        case .sequenceRootConflict:
            return "Failed to register: this sequence starts with a key used by another Nehir command"
        case .hyperLeaderConflict:
            return "Failed to register: this hotkey uses the same physical key as the configured Nehir modifier"
        case .unsupportedHyperModifiers:
            return "Failed to register: Nehir modifier cannot reuse its trigger modifier in the same binding"
        case .unsupportedSequenceHyperStep:
            return "Failed to register: Nehir modifier can only be used as the first sequence key"
        case .inputMonitoringDenied:
            return "Failed to register: sequence hotkeys require Input Monitoring permission"
        case .eventTapUnavailable:
            return "Failed to register: sequence or Nehir modifier capture is unavailable"
        case .systemReserved:
            return "Failed to register: this key combination may be reserved by the system"
        }
    }
}

private struct HotkeyScopeText: View {
    let compatibility: LayoutCompatibility

    var body: some View {
        Text("Scope: \(compatibility.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct HotkeyBindingControl: View {
    let binding: HotkeyTrigger
    let commandName: String
    let isRecordingChord: Bool
    let isRecordingSequenceStep: Bool
    let sequenceDraftSteps: [HotkeySequenceStep]?
    let hyperTrigger: HyperKeyTrigger
    let onStartChordRecording: () -> Void
    let onStartSequenceRecording: () -> Void
    let onCaptured: (KeyBinding) -> Void
    let onSequenceStepCaptured: (KeyBinding) -> Void
    let onAddSequenceStep: () -> Void
    let onApplySequence: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isRecordingChord {
                KeyRecorderView(
                    accessibilityLabel: "Recording hotkey for \(commandName)",
                    hyperTrigger: hyperTrigger,
                    onCapture: onCaptured,
                    onCancel: onCancel
                )
                .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                .accessibilityHint("Press Escape to cancel recording")
            } else if let sequenceDraftSteps {
                HStack(spacing: 6) {
                    ForEach(Array(sequenceDraftSteps.enumerated()), id: \.offset) { _, step in
                        Text(HotkeySettingsDisplayModel.displayString(for: step))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if isRecordingSequenceStep {
                        KeyRecorderView(
                            accessibilityLabel: "Recording sequence key for \(commandName)",
                            allowsBareKeys: true,
                            hyperTrigger: hyperTrigger,
                            onCapture: onSequenceStepCaptured,
                            onCancel: onCancel
                        )
                        .frame(minWidth: 150, idealWidth: 180, minHeight: 34)
                    } else {
                        Button {
                            onAddSequenceStep()
                        } label: {
                            Label("Add sequence key", systemImage: "plus.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Add sequence key")
                        .accessibilityLabel("Add sequence key for \(commandName)")

                        Button("Done") {
                            onApplySequence()
                        }
                        .disabled(sequenceDraftSteps.count < 2)
                    }

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Button {
                        onStartChordRecording()
                    } label: {
                        Text(displayString)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .frame(minWidth: 112, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .help("Change hotkey for \(commandName). Current shortcut: \(humanReadableString)")
                    .accessibilityLabel("Change hotkey for \(commandName)")
                    .accessibilityValue(humanReadableString)

                    Menu {
                        Button("Record Chord") {
                            onStartChordRecording()
                        }
                        Button("Record Sequence") {
                            onStartSequenceRecording()
                        }
                    } label: {
                        Label("Hotkey options for \(commandName)", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Hotkey options")
                    .accessibilityLabel("Hotkey options for \(commandName)")
                }

                if !binding.isUnassigned {
                    Button {
                        onRemove()
                    } label: {
                        Label("Clear hotkey for \(commandName)", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear this hotkey")
                    .accessibilityLabel("Clear hotkey for \(commandName)")
                }
            }
        }
    }

    private var displayString: String {
        HotkeySettingsDisplayModel.displayString(for: binding)
    }

    private var humanReadableString: String {
        HotkeySettingsDisplayModel.humanReadableString(for: binding)
    }
}

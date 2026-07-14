// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import SwiftUI

struct SettingsPage<Content: View>: View {
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        Form {
            if let subtitle {
                Section {
                    SettingsCaption(subtitle)
                }
            }

            content()
        }
        .formStyle(.grouped)
    }
}

struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct SettingsValueText: View {
    let text: String
    var width: CGFloat = 56

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    var valueWidth: CGFloat = 56
    /// Fired when an edit begins/ends. The row commits its own draft on drag end
    /// regardless, so this is purely for optional side effects.
    var onEditingChanged: ((Bool) -> Void)? = nil

    /// Buffered while dragging so each tick does not write through to `value`
    /// (whose `didSet` triggers a synchronous TOML encode + disk write, plus any
    /// `.onChange` side effects, on the main actor). Committed once on drag end.
    @State private var draftValue: Double?

    private var effectiveValue: Double {
        draftValue ?? value
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                let displayText = formatter(effectiveValue)
                Slider(value: Binding(
                    get: { effectiveValue },
                    set: { newValue in
                        draftValue = newValue
                    }
                ), in: range, step: step, onEditingChanged: { editing in
                    if !editing, let draft = draftValue {
                        value = draft
                        draftValue = nil
                    }
                    onEditingChanged?(editing)
                }) {
                    Text(label)
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(displayText)

                SettingsValueText(text: displayText, width: valueWidth)
            }
        }
    }
}

struct SettingsNumberStepperRow: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let valueText: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Stepper(value: $value, step: step) {
                    EmptyView()
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(valueText)

                TextField(label, value: $value, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(label)

                SettingsValueText(text: valueText, width: 60)
            }
        }
    }
}

struct MonitorScopeSection: View {
    @Binding var selectedMonitor: Monitor.ID?
    let monitors: [Monitor]
    let hasOverrides: (Monitor) -> Bool
    let reset: (Monitor) -> Void

    var body: some View {
        Section("Configuration Scope") {
            Picker("Configure", selection: $selectedMonitor) {
                Text("Global Defaults").tag(nil as Monitor.ID?)
                if !monitors.isEmpty {
                    Divider()
                    ForEach(monitors, id: \.id) { monitor in
                        HStack {
                            Text(monitor.name)
                            if monitor.isMain {
                                Text("(Main)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(monitor.id as Monitor.ID?)
                    }
                }
            }

            if let monitorId = selectedMonitor,
               let monitor = monitors.first(where: { $0.id == monitorId })
            {
                LabeledContent("Overrides") {
                    HStack {
                        Text(hasOverrides(monitor) ? "Custom" : "Using global defaults")
                            .foregroundStyle(.secondary)
                        Button("Reset to Global") {
                            reset(monitor)
                        }
                        .disabled(!hasOverrides(monitor))
                    }
                }
            }
        }
    }
}

struct ResetIconButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.uturn.backward.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
    }
}

struct OverridableToggle: View {
    let label: String
    let value: Bool?
    let globalValue: Bool
    let onChange: (Bool) -> Void
    let onReset: () -> Void

    private var effectiveValue: Bool {
        value ?? globalValue
    }

    private var isOverridden: Bool {
        value != nil
    }

    var body: some View {
        LabeledContent {
            HStack {
                Toggle("", isOn: Binding(
                    get: { effectiveValue },
                    set: { onChange($0) }
                ))
                .labelsHidden()
                .accessibilityLabel(label)

                overrideStatus
            }
        } label: {
            Text(label)
        }
    }

    @ViewBuilder
    private var overrideStatus: some View {
        if isOverridden {
            ResetIconButton(title: "Reset \(label) to global default", action: onReset)
        } else {
            Text("Global")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 45)
                .accessibilityLabel("\(label) uses global default")
        }
    }
}

struct OverridablePicker<T: Hashable & Identifiable>: View {
    let label: String
    let value: T?
    let globalValue: T
    let options: [T]
    let displayName: (T) -> String
    let onChange: (T) -> Void
    let onReset: () -> Void

    private var effectiveValue: T {
        value ?? globalValue
    }

    private var isOverridden: Bool {
        value != nil
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Picker(label, selection: Binding(
                    get: { effectiveValue },
                    set: { onChange($0) }
                )) {
                    ForEach(options) { option in
                        Text(displayName(option)).tag(option)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(label)

                overrideStatus
            }
        }
    }

    @ViewBuilder
    private var overrideStatus: some View {
        if isOverridden {
            ResetIconButton(title: "Reset \(label) to global default", action: onReset)
        } else {
            Text("Global")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 45)
                .accessibilityLabel("\(label) uses global default")
        }
    }
}

struct OverridableSlider: View {
    let label: String
    let value: Double?
    let globalValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    let onChange: (Double) -> Void
    let onReset: () -> Void

    /// Buffered while dragging so each tick does not call `onChange` (which writes
    /// through to the persisted setting, triggering a per-tick TOML encode + disk
    /// write on the main actor). Committed once on drag end.
    @State private var draftValue: Double?

    private var effectiveValue: Double {
        draftValue ?? value ?? globalValue
    }

    private var isOverridden: Bool {
        value != nil
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                let displayValue = formatter(effectiveValue)
                Slider(value: Binding(
                    get: { effectiveValue },
                    set: { newValue in
                        draftValue = newValue
                    }
                ), in: range, step: step, onEditingChanged: { editing in
                    if !editing, let draft = draftValue {
                        onChange(draft)
                        draftValue = nil
                    }
                }) {
                    Text(label)
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)

                SettingsValueText(text: displayValue, width: 48)
                overrideStatus
            }
        }
    }

    @ViewBuilder
    private var overrideStatus: some View {
        if isOverridden {
            ResetIconButton(title: "Reset \(label) to global default", action: onReset)
        } else {
            Text("Global")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 45)
                .accessibilityLabel("\(label) uses global default")
        }
    }
}

struct OverridableStepper: View {
    let label: String
    let value: Double?
    let globalValue: Double
    let step: Double
    let formatter: (Double) -> String
    let onChange: (Double) -> Void
    let onReset: () -> Void

    private var effectiveValue: Double {
        value ?? globalValue
    }

    private var isOverridden: Bool {
        value != nil
    }

    private var binding: Binding<Double> {
        Binding(
            get: { effectiveValue },
            set: { onChange($0) }
        )
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                let displayValue = formatter(effectiveValue)
                Stepper(value: binding, step: step) {
                    EmptyView()
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)

                TextField(label, value: binding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(label)

                SettingsValueText(text: displayValue, width: 60)
                overrideStatus
            }
        }
    }

    @ViewBuilder
    private var overrideStatus: some View {
        if isOverridden {
            ResetIconButton(title: "Reset \(label) to global default", action: onReset)
        } else {
            Text("Global")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 45)
                .accessibilityLabel("\(label) uses global default")
        }
    }
}

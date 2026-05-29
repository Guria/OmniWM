import Carbon
import Foundation
@testable import Nehir
import Testing

struct HotkeySettingsViewTests {
    @Test func hotkeyDisplayModelUsesNehirModifierTerminology() {
        let binding = KeyBinding.defaultLeader
        let trigger = HotkeyTrigger.sequence([.leader, .chord(binding)])

        #expect(binding.displayString == "Modifier+Space")
        #expect(binding.humanReadableString == "Modifier+Space")
        #expect(HotkeySettingsDisplayModel.displayString(for: binding) == "Nehir+Space")
        #expect(HotkeySettingsDisplayModel.humanReadableString(for: binding) == "Nehir modifier+Space")
        #expect(HotkeySettingsDisplayModel.displayString(for: trigger) == "Leader, Nehir+Space")
        #expect(HotkeySettingsDisplayModel.humanReadableString(for: trigger) == "Leader, Nehir modifier+Space")
    }

    @Test func hotkeyDisplayModelSearchMatchesVisibleNehirTerminology() {
        let binding = HotkeyBinding(
            id: "focusLeft",
            command: .focus(.left),
            binding: KeyBinding.defaultLeader
        )

        #expect(binding.binding.displayString == "Modifier+Space")
        #expect(HotkeySettingsDisplayModel.matchesSearch("Nehir", binding: binding))
        #expect(HotkeySettingsDisplayModel.matchesSearch("Nehir modifier", binding: binding))
        #expect(!HotkeySettingsDisplayModel.matchesSearch("Hyper", binding: binding))
    }

}

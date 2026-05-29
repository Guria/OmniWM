import Foundation
import NehirIPC
import Testing

@Suite struct IPCSocketPathTests {
    @Test func environmentOverrideWins() {
        let path = "/tmp/omniwm-custom.sock"

        #expect(IPCSocketPath.resolvedPath(environment: [IPCSocketPath.environmentKey: path]) == path)
    }

    @Test func defaultPathUsesOmniWMCachesLocation() {
        let path = IPCSocketPath.resolvedPath(environment: [:], fileManager: .default)

        #expect(path.hasSuffix("/com.nehir/ipc.sock"))
    }

    @Test func secretPathLivesBesideSocketPath() {
        #expect(
            IPCSocketPath.secretPath(forSocketPath: "/tmp/omniwm.sock") == "/tmp/omniwm.sock.secret"
        )
    }
}

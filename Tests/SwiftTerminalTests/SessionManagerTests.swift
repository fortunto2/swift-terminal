import Foundation
import Testing
@testable import SwiftTerminalCore

// MARK: - SessionManager Logic Tests

@Suite("SessionManager — Session Lifecycle")
struct SessionLifecycleTests {
    let server = Server(name: "Test", host: "example.com", username: "deploy")
    let server2 = Server(name: "Prod", host: "prod.example.com", username: "root")

    @MainActor
    @Test("Create session assigns incremental tmux names")
    func createSessionNames() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)
        let s3 = manager.createSession(for: server)

        #expect(s1.tmuxName == "st-0")
        #expect(s2.tmuxName == "st-1")
        #expect(s3.tmuxName == "st-2")
        #expect(manager.sessions.count == 3)
    }

    @MainActor
    @Test("Create session makes it active")
    func createSessionActivates() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        #expect(manager.activeSessionID == s1.id)

        let s2 = manager.createSession(for: server)
        #expect(manager.activeSessionID == s2.id)
    }

    @MainActor
    @Test("Switch to session changes activeSessionID")
    func switchSession() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)

        #expect(manager.activeSessionID == s2.id)
        manager.switchTo(s1.id)
        #expect(manager.activeSessionID == s1.id)
    }

    @MainActor
    @Test("Switch to invalid ID does nothing")
    func switchInvalidID() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        manager.switchTo(UUID()) // random ID
        #expect(manager.activeSessionID == s1.id)
    }

    @MainActor
    @Test("Close session removes it and switches to neighbor")
    func closeSession() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)
        let s3 = manager.createSession(for: server)

        // Active is s3 (last created)
        manager.switchTo(s2.id)
        manager.closeSession(s2.id)

        #expect(manager.sessions.count == 2)
        #expect(!manager.sessions.contains { $0.id == s2.id })
        // Should switch to neighbor (s3 which is now at index 1)
        #expect(manager.activeSessionID == s3.id)
    }

    @MainActor
    @Test("Close last session sets activeSessionID to nil")
    func closeLastSession() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        manager.closeSession(s1.id)

        #expect(manager.sessions.isEmpty)
        #expect(manager.activeSessionID == nil)
    }

    @MainActor
    @Test("Close first active session switches to next")
    func closeFirstSession() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)

        manager.switchTo(s1.id)
        manager.closeSession(s1.id)

        #expect(manager.activeSessionID == s2.id)
    }

    @MainActor
    @Test("CloseAll removes everything")
    func closeAll() {
        let manager = SessionManager()
        _ = manager.createSession(for: server)
        _ = manager.createSession(for: server)
        _ = manager.createSession(for: server)

        manager.closeAll()

        #expect(manager.sessions.isEmpty)
        #expect(manager.activeSessionID == nil)
    }

    @MainActor
    @Test("Sessions for specific server")
    func sessionsPerServer() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        s1.state = .connected
        let s2 = manager.createSession(for: server2)
        s2.state = .connected
        let s3 = manager.createSession(for: server)
        s3.state = .connected

        let forServer1 = manager.activeSessions(for: server)
        #expect(forServer1.count == 2)
        #expect(forServer1.allSatisfy { $0.server.id == server.id })

        let forServer2 = manager.activeSessions(for: server2)
        #expect(forServer2.count == 1)
    }

    @MainActor
    @Test("hasSessions checks any state")
    func hasSessionsAnyState() {
        let manager = SessionManager()
        #expect(!manager.hasSessions(for: server))

        let s1 = manager.createSession(for: server)
        #expect(manager.hasSessions(for: server))

        // Even disconnected sessions count
        s1.state = .disconnected
        #expect(manager.hasSessions(for: server))
    }

    @MainActor
    @Test("connectedCount only counts connected")
    func connectedCount() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)
        let s3 = manager.createSession(for: server)

        s1.state = .connected
        s2.state = .disconnected
        s3.state = .connected

        #expect(manager.connectedCount == 2)
    }
}

// MARK: - Session Model Tests

@Suite("Session — Tmux Naming")
struct SessionTmuxTests {
    let server = Server(name: "Test", host: "example.com")

    @MainActor
    @Test("st-N session is not discovered")
    func stSessionNotDiscovered() {
        let session = Session(server: server, index: 0)
        #expect(session.tmuxName == "st-0")
        #expect(!session.isDiscovered)
    }

    @MainActor
    @Test("Custom tmux name session is discovered")
    func discoveredSession() {
        let session = Session(server: server, tmuxSessionName: "dev")
        #expect(session.tmuxName == "dev")
        #expect(session.isDiscovered)
    }

    @MainActor
    @Test("Session starts in connecting state")
    func initialState() {
        let session = Session(server: server, index: 0)
        #expect(session.state.label == "Connecting...")
        #expect(!session.state.isConnected)
    }
}

// MARK: - RemoteTmuxSession Tests

@Suite("SessionManager — Remote Tmux Sessions")
struct RemoteTmuxSessionTests {
    let server = Server(name: "Test", host: "example.com")

    @MainActor
    @Test("RemoteTmuxSession isOpen when localSessionID set")
    func isOpenLogic() {
        var session = SessionManager.RemoteTmuxSession(
            name: "dev", windowCount: 2, isAttached: false, localSessionID: nil
        )
        #expect(!session.isOpen)

        session.localSessionID = UUID()
        #expect(session.isOpen)
    }

    @MainActor
    @Test("switchToTmuxSession switches and dismisses")
    func switchToTmux() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)
        manager.showTmuxSessionList = true

        manager.switchToTmuxSession(localID: s1.id)

        #expect(manager.activeSessionID == s1.id)
        #expect(!manager.showTmuxSessionList)
    }

    @MainActor
    @Test("attachRemoteTmuxSession creates discovered session")
    func attachRemote() {
        let manager = SessionManager()
        let store = ServerStore()
        _ = manager.createSession(for: server)
        manager.showTmuxSessionList = true

        manager.attachRemoteTmuxSession(name: "work", server: server, store: store)

        #expect(manager.sessions.count == 2)
        let attached = manager.sessions.last!
        #expect(attached.tmuxName == "work")
        #expect(attached.isDiscovered)
        #expect(manager.activeSessionID == attached.id)
        #expect(!manager.showTmuxSessionList)
    }

    @MainActor
    @Test("attachRemoteTmuxSession does not duplicate")
    func attachNoDuplicate() {
        let manager = SessionManager()
        let store = ServerStore()

        // Create a session named "dev" already
        let existing = Session(server: server, tmuxSessionName: "dev")
        manager.sessions.append(existing)
        manager.activeSessionID = existing.id

        manager.attachRemoteTmuxSession(name: "dev", server: server, store: store)

        // Should not create a second one
        #expect(manager.sessions.count == 1)
    }

    @MainActor
    @Test("dismissTmuxSessionList clears state")
    func dismissClears() {
        let manager = SessionManager()
        manager.remoteTmuxSessions = [
            .init(name: "a", windowCount: 1, isAttached: false),
            .init(name: "b", windowCount: 2, isAttached: true),
        ]
        manager.showTmuxSessionList = true

        manager.dismissTmuxSessionList()

        #expect(!manager.showTmuxSessionList)
        #expect(manager.remoteTmuxSessions.isEmpty)
    }
}

// MARK: - Close & Kill Tests

@Suite("SessionManager — Close and Kill")
struct CloseAndKillTests {
    let server = Server(name: "Test", host: "example.com")

    @MainActor
    @Test("closeAndKillSession removes session from list")
    func closeAndKill() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        let s2 = manager.createSession(for: server)

        manager.closeAndKillSession(s1.id)

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == s2.id)
    }

    @MainActor
    @Test("killTmuxSession removes from remoteTmuxSessions")
    func killRemovesFromList() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        s1.state = .connected

        manager.remoteTmuxSessions = [
            .init(name: "dev", windowCount: 1, isAttached: false),
            .init(name: "work", windowCount: 2, isAttached: true),
        ]

        manager.killTmuxSession(name: "dev", via: s1)

        #expect(manager.remoteTmuxSessions.count == 1)
        #expect(manager.remoteTmuxSessions[0].name == "work")
    }

    @MainActor
    @Test("killTmuxSession also closes matching local tab")
    func killClosesLocalTab() {
        let manager = SessionManager()
        let s1 = manager.createSession(for: server)
        s1.state = .connected

        // Add a discovered session for "dev"
        let devSession = Session(server: server, tmuxSessionName: "dev")
        manager.sessions.append(devSession)

        manager.remoteTmuxSessions = [
            .init(name: "dev", windowCount: 1, isAttached: false, localSessionID: devSession.id),
        ]

        manager.killTmuxSession(name: "dev", via: s1)

        // dev session should be removed
        #expect(!manager.sessions.contains { $0.tmuxName == "dev" })
        #expect(manager.remoteTmuxSessions.isEmpty)
    }
}

// MARK: - SessionState Tests

@Suite("SessionState")
struct SessionStateTests {
    @Test("isConnected only for .connected")
    func isConnected() {
        #expect(SessionState.connected.isConnected)
        #expect(!SessionState.connecting.isConnected)
        #expect(!SessionState.disconnected.isConnected)
        #expect(!SessionState.reconnecting(attempt: 1).isConnected)
        #expect(!SessionState.failed("err").isConnected)
    }

    @Test("All states have labels and colors")
    func labelsAndColors() {
        let states: [SessionState] = [
            .connecting, .connected, .disconnected,
            .reconnecting(attempt: 3), .failed("test")
        ]
        for state in states {
            #expect(!state.label.isEmpty)
            // color is always non-nil (SwiftUI.Color)
        }
    }
}

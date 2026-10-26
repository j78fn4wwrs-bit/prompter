import Foundation
import UIKit
import Combine
@preconcurrency import MultipeerConnectivity

/// v1.1 remote control. Peer-to-peer over the local network / Wi-Fi (MultipeerConnectivity).
/// No server, no account. Only control commands and a tiny status go over the link,
/// never script text.
enum RemoteConfig {
    /// Bonjour service type: ≤15 chars, lowercase. Matches NSBonjourServices in Info.plist.
    static let serviceType = "steadyprompt"
}

/// Commands the remote sends to the prompter.
enum RemoteCommand: String, Codable, Sendable, CaseIterable {
    case playPause, speedUp, speedDown, jumpBack, jumpForward, resetToTop
}

/// Marker actions from the remote. Sent as their own message case so older builds simply
/// fail to decode them and ignore them (the existing commands are unchanged).
enum RemoteMarkerCommand: Codable, Sendable, Equatable {
    case add
    case next
    case previous
    /// `key` is the marker's character offset (same key as Script.markerNames).
    case jump(key: Int)
}

/// One marker as the remote shows it.
struct RemoteMarker: Codable, Sendable, Equatable, Identifiable {
    var key: Int
    var name: String
    /// The set timecode, or the estimate when `isEstimate` is true.
    var seconds: Double
    var isEstimate: Bool
    var id: Int { key }
}

/// Status the prompter sends back to the remote.
struct RemoteState: Codable, Sendable, Equatable {
    var isPlaying: Bool
    /// Points per second (same value as the speed slider).
    var speed: Double
    var markerTitle: String?
    /// Optional so older remotes/hosts that don't send or expect them still decode.
    var markers: [RemoteMarker]? = nil
    var currentMarkerKey: Int? = nil
}

enum RemoteMessage: Codable, Sendable {
    case command(RemoteCommand)
    case state(RemoteState)
    case marker(RemoteMarkerCommand)
}

/// Sent as the invitation context. Either the 4-digit code (first pairing)
/// or the saved token (auto-reconnect), plus the token to remember.
struct RemoteInvite: Codable, Sendable {
    var code: String?
    var token: String
}

enum RemoteLinkStatus: Equatable {
    case off, waiting, connecting, connected, disconnected
}

enum RemotePrefKey {
    static let allowRemote = "remote.allow"
    static let hostPairedToken = "remote.host.pairedToken"
    static let hostPairedName = "remote.host.pairedName"
    static let remotePairedToken = "remote.client.pairedToken"
    static let remotePairedHost = "remote.client.pairedHost"
}

/// Thread-safe copy of the values the (nonisolated) invitation callback needs.
private final class PairingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var code = ""
    private var token: String?

    func set(code: String, token: String?) {
        lock.lock(); self.code = code; self.token = token; lock.unlock()
    }

    /// Returns the token to save when the invite is valid, else nil.
    func check(_ invite: RemoteInvite) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = invite.code, !code.isEmpty, c == code { return invite.token }
        if invite.code == nil, let saved = token, saved == invite.token { return invite.token }
        return nil
    }
}

// MARK: - Prompter side (advertises)

@MainActor
final class RemoteHost: NSObject, ObservableObject {
    @Published private(set) var status: RemoteLinkStatus = .off
    @Published private(set) var code: String = ""
    @Published private(set) var remoteName: String?
    /// True while a remote's token is saved on this prompter.
    @Published private(set) var hasPairedRemote: Bool =
        UserDefaults.standard.string(forKey: RemotePrefKey.hostPairedToken) != nil

    /// Commands from the remote, delivered on the main actor.
    let commands = PassthroughSubject<RemoteCommand, Never>()
    let markerCommands = PassthroughSubject<RemoteMarkerCommand, Never>()

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private let gate = PairingGate()
    private var lastState: RemoteState?

    var isRunning: Bool { advertiser != nil }

    func start() {
        guard advertiser == nil else { return }
        code = String(format: "%04d", Int.random(in: 0...9999))
        gate.set(code: code, token: UserDefaults.standard.string(forKey: RemotePrefKey.hostPairedToken))
        let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RemoteConfig.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        status = .waiting
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        status = .off
        remoteName = nil
        lastState = nil
    }

    /// Sends status to the remote (skips if unchanged).
    func send(_ state: RemoteState) {
        guard state != lastState, let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(RemoteMessage.state(state)) else { return }
        lastState = state
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    fileprivate func peerChanged(name: String, state: MCSessionState) {
        switch state {
        case .connected:
            status = .connected
            remoteName = name
            lastState = nil
        case .connecting:
            if status != .connected { status = .connecting }
        case .notConnected:
            // Keep prompting; keep advertising so the remote can come back on its own.
            if session?.connectedPeers.isEmpty ?? true {
                status = advertiser == nil ? .off : .disconnected
            }
        @unknown default:
            break
        }
    }

    fileprivate func paired(token: String, name: String) {
        UserDefaults.standard.set(token, forKey: RemotePrefKey.hostPairedToken)
        UserDefaults.standard.set(name, forKey: RemotePrefKey.hostPairedName)
        gate.set(code: code, token: token)
        hasPairedRemote = true
    }

    /// Deletes the saved remote token and name right away and drops any live connection.
    /// If Allow Remote is still on, it keeps advertising with a fresh code, so the
    /// old remote has to enter the new code to pair again.
    func forgetPairedRemote() {
        UserDefaults.standard.removeObject(forKey: RemotePrefKey.hostPairedToken)
        UserDefaults.standard.removeObject(forKey: RemotePrefKey.hostPairedName)
        gate.set(code: code, token: nil)
        hasPairedRemote = false
        let wasRunning = isRunning
        stop()
        if wasRunning { start() }
    }

    fileprivate func received(_ message: RemoteMessage) {
        switch message {
        case .command(let command): commands.send(command)
        case .marker(let command): markerCommands.send(command)
        case .state: break
        }
    }

    fileprivate var currentSession: MCSession? { session }
}

extension RemoteHost: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let context, let invite = try? JSONDecoder().decode(RemoteInvite.self, from: context),
              let token = gate.check(invite) else {
            invitationHandler(false, nil)
            return
        }
        let name = peerID.displayName
        // The handler must be called with our session, which lives on the main actor.
        nonisolated(unsafe) let handler = invitationHandler
        Task { @MainActor in
            guard let session = self.currentSession else { handler(false, nil); return }
            self.paired(token: token, name: name)
            handler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.status = .disconnected }
    }
}

extension RemoteHost: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        Task { @MainActor in self.peerChanged(name: name, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
        Task { @MainActor in self.received(message) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Remote side (browses)

struct NearbyPrompter: Identifiable, Equatable {
    let id: String   // display name
    let peer: MCPeerID
    var name: String { id }
}

@MainActor
final class RemoteClient: NSObject, ObservableObject {
    @Published private(set) var status: RemoteLinkStatus = .off
    @Published private(set) var nearby: [NearbyPrompter] = []
    @Published private(set) var hostName: String?
    @Published private(set) var state: RemoteState?
    @Published var pairingError: String?

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var connectedPeer: MCPeerID?
    private var pendingToken: String?
    private var pendingHost: String?
    private var usedCode = false

    var savedHost: String? { UserDefaults.standard.string(forKey: RemotePrefKey.remotePairedHost) }

    func start() {
        guard browser == nil else { return }
        let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: RemoteConfig.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        status = .waiting
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        nearby = []
        connectedPeer = nil
        hostName = nil
        state = nil
        status = .off
    }

    /// First-time pairing with the code shown on the prompter.
    func pair(with prompter: NearbyPrompter, code: String) {
        let token = UUID().uuidString
        invite(prompter.peer, invite: RemoteInvite(code: code, token: token), usedCode: true)
    }

    func forgetPairing() {
        UserDefaults.standard.removeObject(forKey: RemotePrefKey.remotePairedToken)
        UserDefaults.standard.removeObject(forKey: RemotePrefKey.remotePairedHost)
        objectWillChange.send()
    }

    func send(_ command: RemoteCommand) {
        guard let session, let peer = connectedPeer,
              let data = try? JSONEncoder().encode(RemoteMessage.command(command)) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    func send(marker command: RemoteMarkerCommand) {
        guard let session, let peer = connectedPeer,
              let data = try? JSONEncoder().encode(RemoteMessage.marker(command)) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    private func invite(_ peer: MCPeerID, invite: RemoteInvite, usedCode: Bool) {
        guard let session, let browser, let data = try? JSONEncoder().encode(invite) else { return }
        pendingToken = invite.token
        pendingHost = peer.displayName
        self.usedCode = usedCode
        pairingError = nil
        status = .connecting
        browser.invitePeer(peer, to: session, withContext: data, timeout: 12)
    }

    fileprivate func found(_ peer: MCPeerID) {
        let item = NearbyPrompter(id: peer.displayName, peer: peer)
        nearby.removeAll { $0.id == item.id }
        nearby.append(item)
        // Auto-reconnect to the remembered prompter.
        if connectedPeer == nil, status != .connecting,
           peer.displayName == savedHost,
           let token = UserDefaults.standard.string(forKey: RemotePrefKey.remotePairedToken) {
            invite(peer, invite: RemoteInvite(code: nil, token: token), usedCode: false)
        }
    }

    fileprivate func lost(name: String) {
        nearby.removeAll { $0.id == name }
    }

    fileprivate func peerChanged(_ peer: MCPeerID, state newState: MCSessionState) {
        switch newState {
        case .connected:
            connectedPeer = peer
            hostName = peer.displayName
            status = .connected
            if let token = pendingToken {
                UserDefaults.standard.set(token, forKey: RemotePrefKey.remotePairedToken)
                UserDefaults.standard.set(peer.displayName, forKey: RemotePrefKey.remotePairedHost)
            }
            pendingToken = nil
        case .connecting:
            status = .connecting
        case .notConnected:
            let wasConnected = connectedPeer?.displayName == peer.displayName
            if wasConnected {
                connectedPeer = nil
                state = nil
                status = .disconnected
                // Browsing keeps running; found(_:) reconnects when the prompter shows up again.
                retryReconnect()
            } else if status == .connecting && peer.displayName == pendingHost {
                status = .waiting
                if usedCode { pairingError = "Couldn't connect. Check the 4-digit code on the prompter and try again." }
                pendingToken = nil
            }
        @unknown default:
            break
        }
    }

    /// Re-invites the remembered prompter if it's still in the nearby list.
    private func retryReconnect() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard self.connectedPeer == nil, self.browser != nil,
                  let saved = self.savedHost,
                  let item = self.nearby.first(where: { $0.id == saved }),
                  let token = UserDefaults.standard.string(forKey: RemotePrefKey.remotePairedToken) else { return }
            self.invite(item.peer, invite: RemoteInvite(code: nil, token: token), usedCode: false)
        }
    }

    fileprivate func received(_ message: RemoteMessage) {
        if case .state(let s) = message { state = s }
    }
}

extension RemoteClient: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        nonisolated(unsafe) let peer = peerID
        Task { @MainActor in self.found(peer) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in self.lost(name: name) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.status = .disconnected }
    }
}

extension RemoteClient: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        nonisolated(unsafe) let peer = peerID
        Task { @MainActor in self.peerChanged(peer, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
        Task { @MainActor in self.received(message) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

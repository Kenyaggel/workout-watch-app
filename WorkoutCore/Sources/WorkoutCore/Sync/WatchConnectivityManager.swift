import Combine
import Foundation
import SwiftData

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity

public final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published public private(set) var lastReceivedTemplateSyncAt: Date?
    @Published public private(set) var lastSentTemplateSyncAt: Date?

    private enum UserInfoKey {
        static let templateSnapshot = "workoutTemplateSnapshot.v1"
    }

    private let modelContainer: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var modelContext: ModelContext?
    private var pendingSnapshot: TemplateSyncSnapshot?
    private var lastSentSnapshot: TemplateSyncSnapshot?

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    @MainActor
    public func activate() {
        guard WCSession.isSupported() else { return }
        if modelContext == nil {
            modelContext = ModelContext(modelContainer)
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        flushPendingSnapshotIfPossible()
    }

    @MainActor
    public func sendTemplateSnapshot(templates: [WorkoutTemplate]) {
        #if os(iOS)
        let snapshot = TemplateSyncSnapshot(templates: templates)
        guard snapshot != lastSentSnapshot else { return }
        pendingSnapshot = snapshot
        flushPendingSnapshotIfPossible()
        #endif
    }

    @MainActor
    private func flushPendingSnapshotIfPossible() {
        #if os(iOS)
        guard
            let snapshot = pendingSnapshot,
            WCSession.isSupported()
        else { return }

        let session = WCSession.default
        guard
            session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else { return }

        do {
            let data = try encoder.encode(snapshot)
            session.transferUserInfo([UserInfoKey.templateSnapshot: data])
            pendingSnapshot = nil
            lastSentSnapshot = snapshot
            lastSentTemplateSyncAt = Date()
        } catch {
            assertionFailure("Failed to encode workout template snapshot: \(error)")
        }
        #endif
    }

    @MainActor
    private func receiveTemplateSnapshot(from userInfo: [String: Any]) {
        #if os(watchOS)
        guard let data = userInfo[UserInfoKey.templateSnapshot] as? Data else { return }
        do {
            let snapshot = try decoder.decode(TemplateSyncSnapshot.self, from: data)
            let context = modelContext ?? ModelContext(modelContainer)
            modelContext = context
            try TemplateSyncImporter.replaceTemplates(with: snapshot, in: context)
            lastReceivedTemplateSyncAt = Date()
        } catch {
            assertionFailure("Failed to import workout template snapshot: \(error)")
        }
        #endif
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.flushPendingSnapshotIfPossible()
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in
            self.receiveTemplateSnapshot(from: userInfo)
        }
    }

    #if os(iOS)
    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#else
public final class WatchConnectivityManager: ObservableObject {
    @Published public private(set) var lastReceivedTemplateSyncAt: Date?
    @Published public private(set) var lastSentTemplateSyncAt: Date?

    public init(modelContainer: ModelContainer) {}

    @MainActor
    public func activate() {}

    @MainActor
    public func sendTemplateSnapshot(templates: [WorkoutTemplate]) {}
}
#endif

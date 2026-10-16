import Foundation

@MainActor
final class ChatRequestController: ObservableObject {
    @Published private(set) var activeSessionIDs: Set<UUID> = []
    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var requests: [UUID: Request] = [:]

    func isActive(_ sessionID: UUID?) -> Bool {
        sessionID.map(activeSessionIDs.contains) ?? false
    }

    func start(
        sessionID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        cancel(sessionID: sessionID)
        let requestID = UUID()
        activeSessionIDs.insert(sessionID)
        let task = Task { [weak self] in
            await operation()
            self?.finish(sessionID: sessionID, requestID: requestID)
        }
        requests[sessionID] = Request(id: requestID, task: task)
    }

    func cancel(sessionID: UUID) {
        requests[sessionID]?.task.cancel()
        requests[sessionID] = nil
        activeSessionIDs.remove(sessionID)
    }

    func cancelAll() {
        requests.values.forEach { $0.task.cancel() }
        requests.removeAll()
        activeSessionIDs.removeAll()
    }

    private func finish(sessionID: UUID, requestID: UUID) {
        guard requests[sessionID]?.id == requestID else { return }
        requests[sessionID] = nil
        activeSessionIDs.remove(sessionID)
    }
}

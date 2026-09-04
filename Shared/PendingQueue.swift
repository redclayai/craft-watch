import Foundation

nonisolated struct PendingCapture: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var text: String
    var destination: CraftAPI.Destination
    var createdAt: Date = Date()
    var attempts: Int = 0
}

/// Disk-backed queue for captures made with no usable connection.
///
/// The point of the whole app is that speaking into your wrist always works, so a failed
/// send must never lose the text.
actor PendingQueue {

    private let url: URL
    private var items: [PendingCapture]

    init(filename: String = "pending-captures.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PendingCapture].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    var all: [PendingCapture] { items }
    var count: Int { items.count }

    func enqueue(_ item: PendingCapture) {
        items.append(item)
        persist()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func recordAttempt(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].attempts += 1
        persist()
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    /// Sends everything it can, keeping whatever still fails. Returns how many landed.
    func flush(using api: CraftAPI) async -> Int {
        var delivered = 0
        for item in items {
            do {
                try await api.capture(item.text, to: item.destination)
                remove(item.id)
                delivered += 1
            } catch {
                recordAttempt(item.id)
                // A hard failure on the first item usually means we are still offline or
                // signed out; stop rather than burning through the whole queue.
                break
            }
        }
        return delivered
    }

    private func persist() {
        SharedDefaults.pendingCount = items.count
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

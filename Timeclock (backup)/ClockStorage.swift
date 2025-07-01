import Foundation

class ClockStorage: ObservableObject {
    @Published var events: [ClockEvent] = []
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("ClockData", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("events.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ClockEvent].self, from: data) {
            events = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL)
        }
    }

    /// Adds a new ClockEvent locally, auto‐assigning a unique local `id`. Returns the assigned `id`.
    func add(event: ClockEvent) -> Int {
      // 1) Look for a duplicate (ignore its id field)
      if let dup = events.first(where: {
           $0.employeeID == event.employeeID &&
           $0.locationID   == event.locationID &&
           $0.action       == event.action &&
           $0.timestamp    == event.timestamp
      }) {
        return dup.id  // already in local storage
      }

      // 2) Otherwise do your normal append & return new localID
        // Determine next local ID (auto‐increment)
        let nextID = (events.map { $0.id }.max() ?? 0) + 1
        var newEvent = event
        newEvent.id = nextID
        events.append(newEvent)
        save()
        return nextID
    }

    /// Updates a given ClockEvent in local storage (by local id).
    func updateEvent(_ updated: ClockEvent) {
        if let index = events.firstIndex(where: { $0.id == updated.id }) {
            events[index] = updated
            save()
        }
    }

    /// Marks the local event (by local id) as synced.
    func markAsSynced(localID: Int) {
        if let index = events.firstIndex(where: { $0.id == localID }) {
            events[index].synced = true
            save()
        }
    }

    /// Updates the `idNUM` (server ID) for the local row matching `localID`, and marks it synced.
    func updateLocalIDNUM(localID: Int, idNUM: Int) {
        if let index = events.firstIndex(where: { $0.id == localID }) {
            events[index].idNUM = idNUM
            events[index].synced = true
            save()
        }
    }

    /// Returns true if a local event already has the given server `idNUM`.
    func existsLocal(idNUM: Int) -> Bool {
        return events.contains { $0.idNUM == idNUM }
    }

    /// Deletes all local events whose timestamp is older than `cutoffMs`.
    func deleteAllOlderThan(timestamp cutoffMs: Int64) {
        events.removeAll { $0.timestamp < cutoffMs }
        save()
    }

    /// Clears all local events.
    func removeAll() {
        events.removeAll()
        save()
    }
}

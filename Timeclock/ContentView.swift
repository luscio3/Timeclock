import SwiftUI
import AppKit
import Combine

// Define pages for navigation
enum Page {
    case home
    case clock
    case admin
    case settings
}

struct ContentView: View {
    @State private var selectedPage: Page = .home
    @StateObject private var storage = ClockStorage()
    @State private var employees: [Employee] = []
    @State private var locations: [Location] = []
    @State private var selectedLocationID: String = UserDefaults.standard.string(forKey: "savedLocationID") ?? ""
    @State private var selectedEmployee: Employee?
    @State private var passcode: String = ""
    @State private var errorMessage: String = ""
    @State private var alwaysOnTop = true
    @State private var clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var remoteEvents: [ClockEvent] = []
    @State private var tick: Int = 0  // drives live updates in HomeView

    // Admin state
    @State private var showAdminPasswordPrompt = false
    @State private var adminPassword = ""
    @State private var showAdminScreen = false

    // For suggestions in clock page
    @State private var employeeName: String = ""
    @State private var suggestions: [String] = []
    @FocusState private var focusedField: Field?

    enum Field { case name, passcode }

    // Combine local & remote to produce "currently clocked in" list:
    var currentClockedInList: [(employeeID: Int, locationID: String, name: String, time: Int64)] {
        currentlyClockedIn(from: storage.events, remoteEvents: remoteEvents, employees: employees)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Side Menu
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { selectedPage = .home }) {
                    Label("Home", systemImage: "house")
                }.padding(.vertical, 8)
                Button(action: { selectedPage = .clock }) {
                    Label("Clock in/out", systemImage: "clock")
                }.padding(.vertical, 8)
                Button(action: { showAdminPasswordPrompt = true }) {
                    Label("Admin Section", systemImage: "lock.shield")
                }.padding(.vertical, 8)
                Button(action: { selectedPage = .settings }) {
                    Label("Settings", systemImage: "gear")
                }.padding(.vertical, 8)
                Spacer()
                Button(action: {
                    alwaysOnTop.toggle()
                    setAlwaysOnTop(alwaysOnTop)
                    errorMessage = alwaysOnTop ? "App is now always on top." : "App is no longer always on top."
                }) {
                    Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                        .scaleEffect(0.75)
                        .padding(8)
                }
            }
            .frame(width: 150)
            .padding(.leading)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Content
            VStack {
                switch selectedPage {
                case .home:
                    HomeView(
                        storage: storage,
                        employees: employees,
                        locations: locations,
                        remoteEvents: remoteEvents,
                        errorMessage: $errorMessage,
                        clockTimer: clockTimer,
                        alwaysOnTop: $alwaysOnTop,
                        loadLocations: loadLocations,
                        loadEmployees: loadEmployees,
                        loadRemoteClockEvents: loadRemoteClockEvents,
                        syncUnsyncedEvents: syncUnsyncedEvents,
                        setAlwaysOnTop: setAlwaysOnTop,
                        tick: tick
                    )
                case .clock:
                    ClockInOutView(
                        storage: storage,
                        employees: employees,
                        locations: locations,
                        remoteEvents: remoteEvents,
                        syncWithServer: syncWithServer,
                        clockTimer: clockTimer,
                        errorMessage: $errorMessage
                       // showPage: $selectedPage
                    )
                case .admin:
                    if showAdminScreen {
                        AdminView(
                            storage: storage,
                            employees: employees,
                            locations: locations,
                            filterEmployee: nil,
                            onExit: { showAdminScreen = false; selectedPage = .home },
                            onSelectEmployee: { _ in }
                        )
                    }
                case .settings:
                    SettingsView(onBack: { selectedPage = .home })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
                    // Initial data load and catch up auto clock-outs
                    storage.removeAll()
                    loadLocations()
                    loadEmployees()
                    loadRemoteClockEvents()
                    handleAutoClockOutIfNeeded() // <- Auto clock-out check at startup
                }
        .onReceive(clockTimer) { _ in
            tick += 1
            syncUnsyncedEvents()
            loadRemoteClockEvents()
            
            // Auto clock-out at end of day
            handleAutoClockOutIfNeeded()
        }
        .sheet(isPresented: $showAdminPasswordPrompt) {
            adminPasswordSheet
        }
    }

    // MARK: - Auto Clock-Out Logic
        /// Checks if current time has passed closing thresholds and auto-clocks out any forgotten clock-ins
        private func handleAutoClockOutIfNeeded() {
            let now = Date()
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: now)
            // Determine closing hour: Mon-Fri 18:30, Sat 17:00
            let closingHour: Int = (2...6).contains(weekday) ? 18 : 17
            let closingMinute: Int = (2...6).contains(weekday) ? 30 : 0
            guard let closingTime = cal.date(bySettingHour: closingHour, minute: closingMinute, second: 0, of: now),
                  now >= closingTime else {
                return
            }
            // Find active clock-ins without matching clock-out today
            let todayStart = cal.startOfDay(for: now)
            let activeIns = storage.events
                .filter { $0.action == "clock_in" && cal.startOfDay(for: Date(timeIntervalSince1970: Double($0.timestamp)/1000)) >= todayStart }
                .filter { ins in
                    !storage.events.contains { evt in
                        evt.action == "clock_out" && evt.employeeID == ins.employeeID && evt.timestamp > ins.timestamp
                    }
                }
            for ins in activeIns {
                let timestamp = Int64(now.timeIntervalSince1970 * 1000)
                let autoOut = ClockEvent(id: 0, idNUM: nil, employeeID: ins.employeeID, locationID: ins.locationID, action: "clock_out", timestamp: timestamp, synced: false)
 //               storage.add(event: autoOut)
                syncWithServer(event: autoOut)
            }
        }
    // MARK: - Admin Password Sheet
    var adminPasswordSheet: some View {
        VStack(spacing: 12) {
            Text("Enter Admin Passcode")
                .font(.headline)

            SecureField("Passcode", text: $adminPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)

            HStack {
                Button("Login") {
                    if let _ = employees.first(where: {
                        ($0.userlevel == 1 || $0.userlevel == 2) &&
                        ($0.password ?? "") == adminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                    }) {
                        showAdminScreen = true
                        selectedPage = .admin
                    } else {
                        errorMessage = "Invalid admin password"
                    }
                    showAdminPasswordPrompt = false
                    adminPassword = ""
                }
                Button("Cancel") {
                    showAdminPasswordPrompt = false
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Data Sync Helpers
    func syncUnsyncedEvents() {
        let unsyncedEvents = storage.events.filter { $0.synced != true }
        for event in unsyncedEvents {
            syncWithServer(event: event)
        }
    }

    func syncWithServer(event: ClockEvent) {
        guard let url = URL(string: "https://altn.cloud/api/clock-event.php") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let payload: [String: Any] = [
            "localID": event.id,
            "employeeID": event.employeeID,
            "locationID": event.locationID,
            "action": event.action,
            "timestamp": event.timestamp
        ]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        errorMessage = "Sync error: \(error.localizedDescription)"
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode),
                          let data = data else
                    {
                        errorMessage = "Server error"
                        return
                    }
                    do {
                        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let assignedServerID = jsonObject["id"] as? Int {
                            storage.updateLocalIDNUM(localID: event.id, idNUM: assignedServerID)
                            storage.markAsSynced(localID: event.id)
                            if event.action == "clock_in" {
                                errorMessage = "Successfully clocked in"
                            } else {
                                errorMessage = "Successfully clocked out"
                            }
                        } else {
                            errorMessage = "Unexpected server response"
                        }
                    } catch {
                        errorMessage = "Parse error: \(error.localizedDescription)"
                    }
                }
            }.resume()
        } catch {
            errorMessage = "Encoding error: \(error.localizedDescription)"
        }
    }

    func loadLocations() {
        guard let url = URL(string: "https://altn.cloud/api/get-locations.php") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data {
                do {
                    let decoded = try JSONDecoder().decode([Location].self, from: data)
                    DispatchQueue.main.async {
                        self.locations = decoded
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to load locations: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    func loadEmployees() {
        guard let url = URL(string: "https://altn.cloud/api/get-employees.php") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data {
                do {
                    let allEmployees = try JSONDecoder().decode([Employee].self, from: data)
                    let filtered = allEmployees.filter { $0.userlevel > 0 }
                    DispatchQueue.main.async {
                        self.employees = filtered
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to load employees: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    func loadRemoteClockEvents() {
        // 1. Calculate timestamp for 3 weeks ago (in milliseconds)
        let threeWeeksAgoMs = Int64(
            Date()
                .addingTimeInterval(-3 * 7 * 24 * 3600)
                .timeIntervalSince1970 * 1000
        )

        // 2. Build URL
        guard let url = URL(
            string: "https://altn.cloud/api/get-clock-events.php?since=\(threeWeeksAgoMs)"
        ) else { return }

        // 3. Fetch remote events
        URLSession.shared.dataTask(with: url) { data, response, error in
            // Network error?
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }

            // No data?
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received from server."
                }
                return
            }

            do {
                // Decode the JSON into ClockEvent objects
                let fetchedRemote = try JSONDecoder().decode([ClockEvent].self, from: data)

                DispatchQueue.main.async {
                    // 4. Purge any local events older than 3 weeks
                    storage.deleteAllOlderThan(timestamp: threeWeeksAgoMs)

                    // 5. Merge fetchedRemote into local storage
                    for remote in fetchedRemote {
                        let existsLocally = storage.events.contains { $0.idNUM == remote.id }
                        if !existsLocally {
                            // Note the `event:` label here to match your API
                            storage.add(event: remote)
                        }
                    }

                    // 6. Update the remoteEvents array for the Clock-In/Out page
                    self.remoteEvents = fetchedRemote
                }

            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode remote events."
                }
            }
        }
        .resume()
    }




    private func mergeRemoteIntoLocal(_ fetchedRemote: [ClockEvent]) {
        for remoteEvent in fetchedRemote {
            if let idNUM = remoteEvent.idNUM, storage.existsLocal(idNUM: idNUM) {
                continue
            }
            var toInsert = remoteEvent
            toInsert.id = 0
            toInsert.synced = true
            let _ = storage.add(event: toInsert)
        }
    }

    func setAlwaysOnTop(_ flag: Bool) {
        if let window = NSApplication.shared.windows.first {
            window.level = flag ? .floating : .normal
        }
    }

    // MARK: - Helpers for work hours

    /// Sum clock-in/out pairs between two Dates, handling shifts that start before the window
    private func hoursWorkedBetweenDates(
        for employeeID: Int,
        events: [ClockEvent],
        start: Date,
        end: Date
    ) -> Double {
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs   = Int64(end.timeIntervalSince1970   * 1000)

        // Only this employee’s events, in chronological order
        let evs = events
          .filter { $0.employeeID == employeeID }
          .sorted { $0.timestamp < $1.timestamp }

        var totalMs: Int64 = 0
        var lastInTs: Int64?

        for ev in evs {
            if ev.action == "clock_in" {
                // If they clocked in before our window, start at window start
                if ev.timestamp <= startMs {
                    lastInTs = startMs
                } else if ev.timestamp < endMs {
                    lastInTs = ev.timestamp
                }
            }
            else if ev.action == "clock_out", let inTs = lastInTs {
                // Out time is capped at window end
                let outTs = min(ev.timestamp, endMs)
                if outTs > inTs {
                    totalMs += (outTs - inTs)
                }
                lastInTs = nil
            }
        }

        // If still “in” at the end, add from lastInTs up to now
        if let inTs = lastInTs, endMs > inTs {
            totalMs += (endMs - inTs)
        }

        return Double(totalMs) / 1000.0 / 3600.0
    }

//    /// Hours worked since last Saturday at midnight
//    private func hoursWorkedSinceLastSaturday(
//        for employeeID: Int,
//        events: [ClockEvent]
//    ) -> Double {
//        let cal = Calendar.current
//        // Find the most recent Saturday on or before today
//        guard let lastSat = cal.nextDate(
//                after: Date(),
//                matching: DateComponents(weekday: 7),      // 7 = Saturday
//                matchingPolicy: .nextTimePreservingSmallerComponents,
//                direction: .backward
//            )
//        else { return 0 }
//
//        let start = cal.startOfDay(for: lastSat)
//        return hoursWorkedBetweenDates(
//            for: employeeID,
//            events: events,
//            start: start,
//            end: Date()
//        )
//    }

//    /// Hours worked today (midnight → now)
//    private func hoursWorkedToday(
//        for employeeID: Int,
//        events: [ClockEvent]
//    ) -> Double {
//        let start = Calendar.current.startOfDay(for: Date())
//        return hoursWorkedBetweenDates(
//            for: employeeID,
//            events: events,
//            start: start,
//            end: Date()
//        )
//    }

    }

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var storage: ClockStorage
    var employees: [Employee]
    var locations: [Location]
    var remoteEvents: [ClockEvent]
    @Binding var errorMessage: String
    var clockTimer: Publishers.Autoconnect<Timer.TimerPublisher>
    @Binding var alwaysOnTop: Bool
    var loadLocations: () -> Void
    var loadEmployees: () -> Void
    var loadRemoteClockEvents: () -> Void
    var syncUnsyncedEvents: () -> Void
    var setAlwaysOnTop: (Bool) -> Void
    var tick: Int

    var currentClockedInList: [(employeeID: Int, locationID: String, name: String, time: Int64)] {
        currentlyClockedIn(from: storage.events, remoteEvents: remoteEvents, employees: employees)
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image("altn_logo").resizable().frame(width: 200, height: 60)
                Spacer()
               
            }
            .padding()

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).padding(.bottom, 10)
            }

            Divider()

            Text("Currently Clocked In:").bold().padding(.top, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(locations) { loc in
                        let locationID = loc.locationNum ?? ""
                        let group = currentClockedInList
                            .filter { $0.locationID == locationID }
                            .sorted { $0.time < $1.time }

                        if !group.isEmpty {
                            Text(loc.location).font(.system(size: 18, weight: .bold))
                            ForEach(group, id: \.employeeID) { entry in
                                let dt = Date(timeIntervalSince1970: Double(entry.time) / 1000)
                                let clockInTime = dt.formatted(date: .omitted, time: .shortened)
                                // recalc including open interval
//                                let hoursPeriod = hoursWorkedSinceLastSaturday(for: entry.employeeID, events: storage.events)
//                                let hoursToday  = hoursWorkedToday(for: entry.employeeID, events: storage.events)

                                HStack(spacing: 4) {
                                    Text("\(entry.name) – \(clockInTime)")
                                        .foregroundColor(
                                            eventSyncStatus(
                                                employeeID: entry.employeeID,
                                                locationID: entry.locationID,
                                                localEvents: storage.events,
                                                remoteEvents: remoteEvents
                                            )
                                        )
//                                    Text(String(format: "(%.2f hrs / %.2f hrs)", hoursPeriod, hoursToday))
//                                        .font(.footnote)
//                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .id(tick) // force live updates
            }
        }
        .padding()
        .onAppear {
            loadLocations()
            loadEmployees()
            loadRemoteClockEvents()
        }
    }
    // ─── Helpers for work hours (make them visible to HomeView) ───

    /// Sum clock‐in/out pairs between two Dates (in hours)
    func hoursWorkedBetweenDates(
        for employeeID: Int,
        events: [ClockEvent],
        start: Date,
        end: Date
    ) -> Double {
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs   = Int64(end.timeIntervalSince1970   * 1000)

        let evs = events
            .filter { $0.employeeID == employeeID }
            .sorted { $0.timestamp < $1.timestamp }

        var totalMs: Int64 = 0
        var lastInTs: Int64?

        for ev in evs {
            if ev.action == "clock_in" {
                if ev.timestamp <= startMs {
                    lastInTs = startMs
                } else if ev.timestamp < endMs {
                    lastInTs = ev.timestamp
                }
            } else if ev.action == "clock_out", let inTs = lastInTs {
                let outTs = min(ev.timestamp, endMs)
                if outTs > inTs { totalMs += (outTs - inTs) }
                lastInTs = nil
            }
        }
        if let inTs = lastInTs, endMs > inTs {
            totalMs += (endMs - inTs)
        }
        return Double(totalMs) / 1000.0 / 3600.0
    }

    /// Two‐week pay period is Saturday → Friday; this coming Friday ends the period
    private func hoursWorkedThisPayPeriod(
      for employeeID: Int,
      events: [ClockEvent]
    ) -> Double {
      let cal = Calendar.current
      guard let nextFri = cal.nextDate(
              after: Date(),
              matching: DateComponents(weekday: 6),  // 6 = Friday
              matchingPolicy: .nextTime
            ) else { return 0 }
      let start = cal.date(byAdding: .day, value: -13, to: nextFri)!
      return hoursWorkedBetweenDates(
        for: employeeID,
        events: events,
        start: start,
        end: Date()
      )
    }
    /// Hours worked since last Saturday at midnight
    func hoursWorkedSinceLastSaturday(
        for employeeID: Int,
        events: [ClockEvent]
    ) -> Double {
        let cal = Calendar.current
        guard let lastSat = cal.nextDate(
            after: Date(),
            matching: DateComponents(weekday: 7), // Saturday
            matchingPolicy: .nextTimePreservingSmallerComponents,
            direction: .backward
        ) else { return 0 }
        let start = cal.startOfDay(for: lastSat)
        return hoursWorkedBetweenDates(
            for: employeeID,
            events: events,
            start: start,
            end: Date()
        )
    }

    /// Hours worked today (midnight → now)
    func hoursWorkedToday(
        for employeeID: Int,
        events: [ClockEvent]
    ) -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        return hoursWorkedBetweenDates(
            for: employeeID,
            events: events,
            start: start,
            end: Date()
        )
    }

}

// MARK: - Settings View
struct SettingsView: View {
    var onBack: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: { onBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.title)
                        .padding()
                }
                Spacer()
            }
            Spacer()
            Text("Settings go here.")
                .font(.headline)
            Spacer()
        }
        .padding()
    }
}


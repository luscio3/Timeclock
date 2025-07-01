import SwiftUI
import Combine

struct ClockInOutView: View {
    // MARK: - Inputs
    @ObservedObject var storage: ClockStorage
    var employees: [Employee]
    var locations: [Location]
    var remoteEvents: [ClockEvent]
    var syncWithServer: (ClockEvent) -> Void
    var clockTimer: Publishers.Autoconnect<Timer.TimerPublisher>
    @Binding var errorMessage: String

    // MARK: - State
    @State private var selectedLocationID: String = UserDefaults.standard.string(forKey: "savedLocationID") ?? ""
    @State private var selectedEmployee: Employee?
    @State private var passcode: String = ""
    @State private var employeeName: String = ""
    @State private var suggestions: [String] = []
    @State private var showHistory: Bool = false
    @FocusState private var focusedField: Field?

    enum Field { case name, passcode }

    var body: some View {
        VStack(spacing: 15) {
            // Error banner
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.bottom, 10)
            }

            // Clock form
            VStack(alignment: .leading, spacing: 8) {
                // Location picker
                if selectedLocationID.isEmpty {
                    Picker("Location", selection: $selectedLocationID) {
                        Text("Select a Location").tag("")
                        ForEach(locations) { loc in
                            if let id = loc.locationNum {
                                Text(loc.location).tag(id)
                            }
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                // Employee name with autocomplete
                TextField("Employee Name", text: $employeeName)
                    .focused($focusedField, equals: .name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: employeeName) { newValue in
                        suggestions = employees.map { $0.fullName }
                            .filter { $0.lowercased().hasPrefix(newValue.lowercased()) }
                    }
                    .onSubmit {
                        if let match = suggestions.first {
                            employeeName = match
                            selectedEmployee = employees.first { $0.fullName == match }
                        }
                        focusedField = .passcode
                    }
                    .onChange(of: selectedEmployee) { _ in
                        // hide history when employee changes
                        showHistory = false
                    }

                // Passcode input
                SecureField("Passcode", text: $passcode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                // Action buttons
                HStack(spacing: 16) {
                    Button("Clock In") { clock(action: "clock_in") }
                        .disabled(clockInDisabled)
                    Button("Clock Out") { clock(action: "clock_out") }
                        .disabled(clockOutDisabled)
                    Button("Recent Events") { showRecentEvents() }
                        .disabled(selectedEmployee == nil || selectedLocationID.isEmpty)
                }
            }
            .frame(width: 360)

            // Inline history view
            if showHistory {
                ClockEventHistoryView(
            //        storage: storage,
                    remoteEvents: remoteEvents,
                    employees: employees,
                    locations: locations,
                    toDate: toDate,
                    sendChangeRequest: sendChangeRequest
                )
                .frame(maxHeight: 400)
            }

            Spacer()
        }
        .padding()
        .onChange(of: selectedLocationID) { new in
            UserDefaults.standard.set(new, forKey: "savedLocationID")
            showHistory = false // hide on location change
        }
        .onReceive(clockTimer) { _ in
            storage.events.filter { !$0.synced }.forEach(syncWithServer)
        }
        .onChange(of: errorMessage) { val in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if errorMessage == val { errorMessage = "" }
            }
        }
    }

    // MARK: - Computed Flags
    private var clockInDisabled: Bool {
        guard let emp = selectedEmployee else { return true }
        return selectedLocationID.isEmpty || currentlyClockedInList.contains { $0.employeeID == emp.id }
    }
    private var clockOutDisabled: Bool {
        guard let emp = selectedEmployee else { return true }
        return selectedLocationID.isEmpty || !currentlyClockedInList.contains { $0.employeeID == emp.id }
    }

    private var currentlyClockedInList: [(employeeID: Int, locationID: String, name: String, time: Int64)] {
        currentlyClockedIn(from: storage.events, remoteEvents: remoteEvents, employees: employees)
    }

    // MARK: - Actions
    private func showRecentEvents() {
        guard let emp = selectedEmployee else {
            errorMessage = "Select employee first"
            return
        }
        guard emp.password == passcode else {
            errorMessage = "Incorrect passcode"
            return
        }
        showHistory.toggle()
        passcode = ""
    }

    private func clock(action: String) {
        guard let emp = selectedEmployee else {
            errorMessage = "Please select a valid employee"
            return
        }
        let isIn = currentlyClockedInList.contains { $0.employeeID == emp.id }
        if action == "clock_in" {
            guard !isIn else { errorMessage = "Already clocked in"; return }
        } else {
            guard isIn else { errorMessage = "Not clocked in"; return }
        }
        guard emp.password == passcode else {
            errorMessage = "Incorrect passcode"
            return
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var newEvent = ClockEvent(
            id: 0,
            idNUM: nil,
            employeeID: emp.id,
            locationID: selectedLocationID,
            action: action,
            timestamp: nowMs,
            synced: false
        )
        newEvent.id = storage.add(event: newEvent)
        syncWithServer(newEvent)
        errorMessage = ""
    }

    // MARK: - Delegate helpers for history view
    private func toDate(_ ts: Int64) -> Date {
        if ts > 1_000_000_000_000_000 { return Date(timeIntervalSince1970: Double(ts) / 1_000_000) }
        if ts > 1_000_000_000_000     { return Date(timeIntervalSince1970: Double(ts) / 1_000) }
        return Date(timeIntervalSince1970: Double(ts))
    }

    private func sendChangeRequest(_ event: ClockEvent) {
        guard let url = URL(string: "https://altn.cloud/api/clock-event-requests.php") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let params: [String: Any] = [
            "id":       event.idNUM ?? 0,
            "employee_id": event.employeeID,
            "location": event.locationID,
            "action":   event.action,
            "timestamp": event.timestamp,
            "previous": 0,
            "approved": 0
        ]
        let bodyString = params.map { key, value in
            "\(key)=\(String(describing: value).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }.joined(separator: "&")
        req.httpBody = bodyString.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req).resume()
    }
}

import SwiftUI

struct EditEventView: View {
    @Environment(\.dismiss) var dismiss

    var event: ClockEvent?
    let employees: [Employee]
    let locations: [Location]
    var onSave: (ClockEvent) -> Void

    @State private var selectedEmployee: Employee?
    @State private var selectedLocationID: String = ""
    @State private var selectedAction: String = "clock_in"
    @State private var timestamp: Date = Date()

    var body: some View {
        NavigationView {
            Form {
                Picker("Employee", selection: $selectedEmployee) {
                    ForEach(employees) { emp in
                        Text(emp.fullName).tag(Optional(emp))
                    }
                }
                .onChange(of: selectedEmployee) { newValue in
                    if let emp = newValue {
                        selectedLocationID = emp.locationID ?? ""
                    }
                }

                Picker("Select Location", selection: $selectedLocationID) {
                    ForEach(locations, id: \.locationNum) { loc in
                        Text(loc.location).tag(loc.locationNum)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                Picker("Action", selection: $selectedAction) {
                    Text("Clock In").tag("clock_in")
                    Text("Clock Out").tag("clock_out")
                }
                .pickerStyle(.segmented)

                DatePicker("Timestamp", selection: $timestamp)
            }
            .navigationTitle(event == nil ? "Add Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let emp = selectedEmployee else { return }

                        let newEvent = ClockEvent(
                            id: event?.id ?? 0,
                            idNUM: event?.idNUM,
                            employeeID: emp.id,
                            locationID: selectedLocationID,
                            action: selectedAction,
                            timestamp: Int64(timestamp.timeIntervalSince1970 * 1000),
                            synced: false
                        )

                        onSave(newEvent)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .frame(width: 400, height: 300)
        }
        .frame(width: 400, height: 300)
        .onAppear {
            if let ev = event {
                selectedEmployee = employees.first(where: { $0.id == ev.employeeID })
                selectedLocationID = ev.locationID
                selectedAction = ev.action
                timestamp = ev.date

                // 🧪 Debug output
                print("event.locationID: \(ev.locationID)")
                print("available location tags: \(locations.map { String($0.locationNum ?? "") })")
            }
        }
    }
}


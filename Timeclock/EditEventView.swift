import SwiftUI

// Define the ChangeRequest model if it’s not already defined elsewhere
struct ChangeRequest: Codable {
    let id: Int
    let employeeID: Int
    let action: String
    let timestamp: Int64
    let locationID: String
}

struct EditEventView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var inEvent: ClockEvent
    let onSubmit: (ChangeRequest) -> Void

    @State private var editDate: Date

    /// Initialize editDate from the event’s Unix-ms timestamp
    init(inEvent: Binding<ClockEvent>, onSubmit: @escaping (ChangeRequest) -> Void) {
        self._inEvent = inEvent
        self.onSubmit = onSubmit
        let tsSeconds = TimeInterval(inEvent.wrappedValue.timestamp) / 1_000
        self._editDate = State(initialValue: Date(timeIntervalSince1970: tsSeconds))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Request for Event ID \(inEvent.idNUM ?? 0)")
                .font(.headline)
                .padding(.top)

            Form {
                Section(header: Text("Event Details")) {
                    HStack {
                        Text("ID")
                        Spacer()
                        Text("\(inEvent.idNUM ?? 0)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Employee ID")
                        Spacer()
                        Text("\(inEvent.employeeID)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Action")
                        Spacer()
                        Text(inEvent.action)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(inEvent.locationID)
                            .foregroundColor(.secondary)
                    }
                    DatePicker(
                        "Timestamp",
                        selection: $editDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                Section {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        Spacer()
                        Button("Submit") {
                            let newTimestamp = Int64(editDate.timeIntervalSince1970 * 1000)
                            let change = ChangeRequest(
                                id: inEvent.idNUM ?? 0,
                                employeeID: inEvent.employeeID,
                                action: inEvent.action,
                                timestamp: newTimestamp,
                                locationID: inEvent.locationID
                            )
                            onSubmit(change)
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .frame(width: 320, height: 380)
        }
        .frame(width: 360, height: 440)
    }
}


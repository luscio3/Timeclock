// MARK: - RequestEdit.swift
import SwiftUI

struct RequestEdit: View {
    let event: ClockEvent
    let locations: [Location]
    let toDate: (Int64) -> Date
    let onSubmit: (ClockEvent) -> Void
    let onCancel: () -> Void

    @State private var selectedDate: Date
    @State private var isPosting: Bool = false

    init(event: ClockEvent,
         locations: [Location],
         toDate: @escaping (Int64) -> Date,
         onSubmit: @escaping (ClockEvent) -> Void,
         onCancel: @escaping () -> Void) {
        self.event = event
        self.locations = locations
        self.toDate = toDate
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _selectedDate = State(initialValue: toDate(event.timestamp))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Request for Event #\(event.idNUM ?? 0)")
                .font(.headline)

            DatePicker("New Date & Time", selection: $selectedDate)
                .datePickerStyle(FieldDatePickerStyle())
                .labelsHidden()

            HStack(spacing: 20) {
                Button(action: submitRequest) {
                    if isPosting { ProgressView() }
                    else { Text("Submit") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPosting)

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .disabled(isPosting)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }

    private func submitRequest() {
        isPosting = true
        var updated = event
        updated.timestamp = Int64(selectedDate.timeIntervalSince1970 * 1000)

        guard let url = URL(string: "https://altn.cloud/api/clock_events_requests.php") else {
                    print("⚠️ Invalid URL")
                    isPosting = false
                    return
                }
        let body: [String: Any] = [
            "id":          updated.idNUM ?? 0,
            "employeeID":  updated.employeeID,
            "action":      updated.action,
            "timestamp":   updated.timestamp,
            "locationID":  updated.locationID
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
                    DispatchQueue.main.async { isPosting = false }

                    if let err = err {
                        print("Network error:", err)
                        return
                    }
                    if let http = resp as? HTTPURLResponse {
                        print("HTTP status code:", http.statusCode)
                    }
                    guard let d = data else {
                        print("No data in response")
                        return
                    }
                    if let text = String(data: d, encoding: .utf8) {
                        print("Response body:", text)
                    }
                    guard let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let success = json["success"] as? Bool else {
                        print("Server error or invalid response")
                        return
                    }
                    if success {
                        DispatchQueue.main.async {
                            onSubmit(updated)
                        }
                    } else {
                        print("Server returned success = false")
                    }
                }.resume()
            }
        }

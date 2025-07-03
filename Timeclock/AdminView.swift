// AdminView.swift
// Updated to fix Date formatting closure error and refine the sheet binding
import SwiftUI
import AppKit
import Foundation

struct AdminView: View {
    @ObservedObject var storage: ClockStorage
    let employees: [Employee]
    let locations: [Location]
    let filterEmployee: Employee?
    let onExit: () -> Void
    let onSelectEmployee: (Employee?) -> Void

    @State private var selectedEmployee: Employee? = nil
    @State private var editingEvent: ClockEvent? = nil
    @State private var remoteEvents: [ClockEvent] = []

    var filteredEvents: [ClockEvent] {
        let source = remoteEvents.isEmpty ? storage.events : remoteEvents
        guard let sel = selectedEmployee else { return source }
        return source.filter { $0.employeeID == sel.id }
    }

    var body: some View {
        VStack {
            // Employee filter and payroll buttons
            HStack {
                Button("Show All") { selectedEmployee = nil }
                Spacer()
                Button("Payroll") { generatePayrollPDF() }
            }
            .padding(.horizontal)

            // Employee selection grid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(employees.filter { $0.userlevel > 2 }, id: \ .id) { emp in
                        Button(emp.fullName) { selectedEmployee = emp }
                            .padding(6)
                            .background(selectedEmployee?.id == emp.id ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

            // Events table
            Table(filteredEvents) {
                TableColumn("Employee") { event in
                    Text(employees.first(where: { $0.id == event.employeeID })?.fullName ?? "")
                }
                TableColumn("Action") { event in
                    Text(event.action)
                }
                TableColumn("Location") { event in
                    Text(locations.first(where: { String($0.id) == event.locationID })?.location ?? "Unknown")
                }
                TableColumn("Time") { event in
                    // Use Date formatted directly inside Text initializer
                    Text(event.date, style: .time)
                }
                TableColumn("Edit") { event in
                    Button("Edit") { editingEvent = event }
                }
            }
            .sheet(item: $editingEvent) { event in
                if let idx = remoteEvents.firstIndex(where: { $0.id == event.id }) {
                    EditEventView(inEvent: $remoteEvents[idx]) { change in
                        applyChangeRequest(change)
                    }
                } else if let idx = storage.events.firstIndex(where: { $0.id == event.id }) {
                    EditEventView(inEvent: Binding(
                        get: { storage.events[idx] },
                        set: { storage.events[idx] = $0 }
                    )) { change in
                        applyChangeRequest(change)
                    }
                }
            }

            // Exit button
            Button("Exit Admin") { onExit() }
                .padding()
        }
        .task { await loadRemoteEvents() }
    }

    // MARK: - Actions

    func applyChangeRequest(_ change: ChangeRequest) {
        Task {
            await sendChangeToServer(change)
            await loadRemoteEvents()
        }
    }

    func sendChangeToServer(_ change: ChangeRequest) async {
        // Implement your network call here
    }

    func generatePayrollPDF() {
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!

        context.beginPDFPage(nil)
        let title = "Payroll Report"
        let attrs = [
            NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 24)
        ]
        title.draw(at: CGPoint(x: 72, y: 72), withAttributes: attrs)

        var y = 120.0
        for emp in employees.filter({ $0.userlevel > 2 }) {
            let reg = totalHours(for: emp.id, filter: "regular")
            let ot = totalHours(for: emp.id, filter: "overtime")
            let line = "\(emp.fullName): Regular: \(reg), OT: \(ot)"
            line.draw(at: CGPoint(x: 72, y: y), withAttributes: nil)
            y += 20
        }

        context.endPDFPage()
        context.closePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PayrollReport.pdf")
        pdfData.write(to: url, atomically: true)
        NSWorkspace.shared.open(url)
    }

    func totalHours(for employeeID: Int, filter: String) -> String {
        let count = storage.events.filter { $0.employeeID == employeeID && $0.action == "clock_out" }.count
        return String(format: "%.2f", Double(count))
    }

    func loadRemoteEvents() async {
        guard let url = URL(string: "https://altn.cloud/api/get-clock-events.php") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([ClockEvent].self, from: data)
            DispatchQueue.main.async {
                remoteEvents = decoded
            }
        } catch {
            print("Failed to load remote events:", error)
        }
    }
}

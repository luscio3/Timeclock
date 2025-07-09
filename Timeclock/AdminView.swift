// AdminView.swift
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
        let sourceEvents = remoteEvents.isEmpty ? storage.events : remoteEvents
        if let selected = selectedEmployee {
            return sourceEvents.filter { $0.employeeID == selected.id }
        }
        return sourceEvents
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                HStack {
                    Button("Show All") {
                        selectedEmployee = nil
                    }
                    Spacer()
                    Button("Payroll") {
                        generatePayrollPDF()
                    }
                }

                let employeeButtons = employees.filter { $0.userlevel > 2 }
                let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10)]

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(employeeButtons, id: \ .id) { emp in
                            Button(action: {
                                selectedEmployee = emp
                            }) {
                                Text(emp.fullName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(selectedEmployee?.id == emp.id ? Color.blue.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding()

            Table(filteredEvents) {
                TableColumn("Employee") { event in
                    if let emp = employees.first(where: { $0.id == event.employeeID }) {
                        Text(emp.fullName)
                    }
                }
                TableColumn("Action") { Text($0.action) }
                TableColumn("Location") { event in
                    if let loc = locations.first(where: { String($0.id) == event.locationID }) {
                        Text(loc.location)
                    } else {
                        Text("Unknown")
                    }
                }

                TableColumn("Time") { (event: ClockEvent) in
                    Text(event.date.formatted(date: .abbreviated, time: .shortened))
                }
                TableColumn("Edit") { event in
                    Button("Edit") {
                        editingEvent = event
                    }
                }
            }
            .sheet(item: $editingEvent) { event in
                EditEventView(
                    event: event,
                    employees: employees,
                    locations: locations,
                    onSave: { updatedEvent in
                        storage.updateEvent(updatedEvent)
                    }
                )
                .frame(width: 400)
            }

            Button("Exit Admin") {
                onExit()
            }
            .padding()
        }
        .task {
            await loadRemoteEvents()
        }
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
            let regHours = totalHours(for: emp.id, filter: "regular")
            let otHours = totalHours(for: emp.id, filter: "overtime")
            let line = "\(emp.fullName): Regular: \(regHours), OT: \(otHours)"
            line.draw(at: CGPoint(x: 72, y: y), withAttributes: nil)
            y += 20
        }

        context.endPDFPage()
        context.closePDF()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PayrollReport.pdf")
        pdfData.write(to: tempURL, atomically: true)
        NSWorkspace.shared.open(tempURL)
    }

    func totalHours(for employeeID: Int, filter: String) -> String {
        let total = storage.events
            .filter { $0.employeeID == employeeID && $0.action == "clock_out" }
            .count
        return String(format: "%.2f", Double(total))
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

import SwiftUI

// Formatter for weekday names
private let weekdayFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "EEEE"
  return f
}()

// MARK: - WeekGroup Model
/// Represents a week-range of clock events.
struct WeekGroup: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let pairs: [(inEvent: ClockEvent, outEvent: ClockEvent?)]
}



// MARK: - Grouping Logic
/// Extracts the three most recent weeks (Saturday–Friday) from remote clock events.
func weeklyGroups(from remoteEvents: [ClockEvent]) -> [WeekGroup] {
    let now = Date()
    let cal = Calendar.current
    // Find the most recent Saturday at or before today
    let weekdayComponent = cal.component(.weekday, from: now)
    // Saturday = 7
    let daysSinceSaturday = (weekdayComponent >= 7 ? weekdayComponent - 7 : weekdayComponent + (7 - 7))
    guard let thisWeekStart = cal.date(byAdding: .day, value: -daysSinceSaturday, to: now) else {
        return []
    }
    let startOfThisWeek = cal.startOfDay(for: thisWeekStart)

    // Build the last three week ranges
    var weekRanges: [(start: Date, end: Date)] = []
    for i in 0..<3 {
        let start = cal.date(byAdding: .day, value: -7 * i, to: startOfThisWeek)!
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        weekRanges.append((start: start, end: end))
    }

    let all = remoteEvents.sorted { $0.timestamp < $1.timestamp }
    func toDate(_ ts: Int64) -> Date { Date(timeIntervalSince1970: Double(ts) / 1000) }

    return weekRanges.map { range in
        let eventsInWeek = all.filter { ev in
            let d = toDate(ev.timestamp)
            return d >= range.start && d <= range.end
        }
        var pairs: [(inEvent: ClockEvent, outEvent: ClockEvent?)] = []
        var lastIn: ClockEvent? = nil
        for ev in eventsInWeek {
            if ev.action == "clock_in" {
                lastIn = ev
            } else if ev.action == "clock_out", let cin = lastIn {
                pairs.append((inEvent: cin, outEvent: ev))
                lastIn = nil
            }
        }
        // Include any unmatched clock_in as an open pair
        if let cin = lastIn {
            pairs.append((inEvent: cin, outEvent: nil))
        }
        return WeekGroup(startDate: range.start, endDate: range.end, pairs: pairs)
    }
}

// MARK: - ChangeRequestSheet Stub
/// Stub for editing a clock event. Replace with your real UI.
struct ChangeRequestSheet: View {
    let event: ClockEvent
    let locations: [Location]
    let toDate: (Int64) -> Date
    let onSubmit: (ClockEvent) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Change Request for Event ID \(event.idNUM ?? 0)")
                .font(.headline)
            // TODO: Add your form fields for editing
            HStack(spacing: 12) {
                Button("Submit") { onSubmit(event) }
                Button("Cancel") { onCancel() }
            }
        }
        .padding()
    }
}

// MARK: - Clock Event History View
struct ClockEventHistoryView: View {
    var remoteEvents: [ClockEvent]
    var employees: [Employee]
    var locations: [Location]
    var toDate: (Int64) -> Date
    var sendChangeRequest: (ClockEvent) -> Void

    @State private var editingEvent: ClockEvent? = nil
    private let calendar = Calendar.current

    // JSON encoder for raw display
    private var rawJson: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(remoteEvents),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Recent Events (3 Weeks)")
                    .font(.title2)
                    .padding(.top)

                ForEach(weeklyGroups(from: remoteEvents)) { group in
                    VStack(spacing: 6) {
                        Text("\(Self.dateFormatter.string(from: group.startDate)) – " +
                             "\(Self.dateFormatter.string(from: group.endDate))")
                            .font(.headline)
                        ForEach(group.pairs, id: \.inEvent.timestamp) { pair in
                            let name    = employees.first { $0.id == pair.inEvent.employeeID }?.fullName ?? "Unknown"
                            let inDate  = toDate(pair.inEvent.timestamp)
                            let outDate = pair.outEvent.map { toDate($0.timestamp) }
                            Group {
                                HStack(spacing: 16) {
                                    Text(weekdayFormatter.string(from: inDate))
                                        .frame(width: 120, alignment: .leading)
                                    Text(Self.timeFormatter.string(from: inDate))
                                        .frame(width: 100)
                                    if let od = outDate {
                                        Text(Self.timeFormatter.string(from: od))
                                            .frame(width: 100)
                                    } else {
                                        Text("--").frame(width: 100)
                                    }
                                    Text(durationText(pair: pair))
                                        .frame(width: 100)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editingEvent = pair.inEvent }
                            }
                        }
                        HStack { Spacer(); Text(weekTotalText(group: group)).bold(); Spacer() }
                        Divider()
                    }
                    .padding(.vertical, 6)
                }

                // Raw JSON display
                Divider().padding(.top)
                Text("Raw JSON:")
                    .font(.headline)
                ScrollView(.horizontal) {
                    Text(rawJson)
                        .font(.system(.body, design: .monospaced))
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
        }
        .sheet(item: $editingEvent) { event in
            ChangeRequestSheet(
                event: event,
                locations: locations,
                toDate: toDate,
                onSubmit: { ev in sendChangeRequest(ev); editingEvent = nil },
                onCancel: { editingEvent = nil }
            )
        }
    }

    private func durationText(pair: (inEvent: ClockEvent, outEvent: ClockEvent?)) -> String {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let outTs = pair.outEvent?.timestamp ?? nowMs
        let durSec = (outTs - pair.inEvent.timestamp) / 1000
        let h = durSec / 3600; let m = (durSec % 3600) / 60
        return String(format: "%02dh %02dm", h, m)
    }

    private func weekTotalText(group: WeekGroup) -> String {
        let totalSec = group.pairs.reduce(Int64(0)) { sum, p in
            let outTs = p.outEvent?.timestamp ?? Int64(Date().timeIntervalSince1970 * 1000)
            return sum + (outTs - p.inEvent.timestamp) / 1000
        }
        let h = totalSec / 3600; let m = (totalSec % 3600) / 60
        return "Total: \(h)h \(m)m"
    }
}


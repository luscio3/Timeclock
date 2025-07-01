import SwiftUI
import Foundation

extension ClockEvent {
    var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}

func filteredEmployees(_ employees: [Employee], matching name: String) -> [Employee] {
    guard !name.isEmpty else { return employees }
    let lowercasedInput = name.lowercased()
    return employees.filter { $0.fullName.lowercased().contains(lowercasedInput) }
}

func eventSyncStatus(employeeID: Int, locationID: String, localEvents: [ClockEvent], remoteEvents: [ClockEvent]) -> Color {
    let local = localEvents.contains { $0.employeeID == employeeID && $0.locationID == locationID }
    let remote = remoteEvents.contains { $0.employeeID == employeeID && $0.locationID == locationID }
    switch (local, remote) {
    case (true, true): return .green
    case (true, false): return .purple
    case (false, true): return .blue
    default: return .primary
    }
}

func currentlyClockedIn(from localEvents: [ClockEvent], remoteEvents: [ClockEvent], employees: [Employee]) -> [(employeeID: Int, locationID: String, name: String, time: Int64)] {
    let eventSource = remoteEvents.isEmpty ? localEvents : remoteEvents
    var clockedIn: [Int: ClockEvent] = [:]
    for event in eventSource.sorted(by: { $0.timestamp < $1.timestamp }) {
        if event.action == "clock_in" {
            clockedIn[event.employeeID] = event
        } else if event.action == "clock_out" {
            clockedIn.removeValue(forKey: event.employeeID)
        }
    }
    return clockedIn.compactMap { (id, event) in
        if let emp = employees.first(where: { $0.id == id && $0.userlevel > 2 }) {
            return (id, event.locationID, emp.fullName, event.timestamp)
        }
        return nil
    }
}

func totalHoursThisWeek(for employeeID: Int, events: [ClockEvent]) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()

    var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
    components.weekday = 1 // Sunday
    guard let weekStart = calendar.date(from: components) else {
        return "0.00"
    }

    let filtered = events
        .filter {
            $0.employeeID == employeeID && $0.date >= weekStart
        }
        .sorted { $0.timestamp < $1.timestamp }

    var total: TimeInterval = 0
    var lastClockIn: Date? = nil

    for event in filtered {
        let eventTime = event.date
        if event.action == "clock_in" {
            lastClockIn = eventTime
        } else if event.action == "clock_out", let clockInTime = lastClockIn {
            total += eventTime.timeIntervalSince(clockInTime)
            lastClockIn = nil
        }
    }

    if let inTime = lastClockIn {
        total += now.timeIntervalSince(inTime)
    }

    return String(format: "%.2f", total / 3600)
}

func timeElapsedString(from date: Date) -> String {
  // your implementation, e.g.:
  let interval = Int(Date().timeIntervalSince(date))
  let hours = interval / 3600
  let minutes = (interval % 3600) / 60
  return String(format: "%02d:%02d", hours, minutes)
}

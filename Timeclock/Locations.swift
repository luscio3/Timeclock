// Locations.swift
import Foundation

struct Location: Identifiable, Codable, Hashable, Equatable {
    var id: Int
    var location: String
    var franchise: String?
    var locationNum: String?
}

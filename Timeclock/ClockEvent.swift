import Foundation

struct ClockEvent: Identifiable, Codable {
    // Local auto‐increment primary key (e.g. SQLite/Core Data) assigned on save
    var id: Int
    
    // Server‐assigned ID (MySQL). Nil until synced to server.
    var idNUM: Int?
    
    var employeeID: Int
    var locationID: String
    var action: String
    var timestamp: Int64  // milliseconds since 1970
    
    // Whether this event has been synced to server (idNUM populated)
    var synced: Bool
    
    // MARK: – CodingKeys for Codable
    // Only these fields are encoded/decoded against the server.
    enum CodingKeys: String, CodingKey {
        case idNUM = "id"
        case employeeID
        case locationID
        case action
        case timestamp
    }

    // MARK: – Custom Decodable initializer
    // When the server returns JSON, it will decode only the fields in CodingKeys.
    // We then set id = 0 (dummy), and synced = true (because these came from the server).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idNUM = try container.decodeIfPresent(Int.self, forKey: .idNUM)
        self.employeeID = try container.decode(Int.self, forKey: .employeeID)
        self.locationID = try container.decode(String.self, forKey: .locationID)
        self.action = try container.decode(String.self, forKey: .action)
        self.timestamp = try container.decode(Int64.self, forKey: .timestamp)

        // Remote‐origin events: we haven’t assigned a local ID yet,
        // and we consider them “synced” because they came from MySQL.
        self.id = 0
        self.synced = true
    }

    // MARK: – Memberwise initializer (for creating brand‐new local events)
    init(
        id: Int,
        idNUM: Int?,
        employeeID: Int,
        locationID: String,
        action: String,
        timestamp: Int64,
        synced: Bool
    ) {
        self.id = id
        self.idNUM = idNUM
        self.employeeID = employeeID
        self.locationID = locationID
        self.action = action
        self.timestamp = timestamp
        self.synced = synced
    }
    
    // MARK: – Encodable is synthesized automatically, including only the CodingKeys
    // (so “id” and “synced”/local fields are not sent to the server).
}


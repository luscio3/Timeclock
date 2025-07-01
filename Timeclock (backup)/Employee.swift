struct Employee: Identifiable, Codable, Hashable, Equatable {
    var id: Int
    var firstName: String
    var lastName: String
    var phone: String
    var password: String?
    var userlevel: Int
    var locationID: String?

    var fullName: String { "\(firstName) \(lastName)" }
}

import Foundation

struct EmergencyContact: Codable {
    var name: String?
    var phone: String?
}

struct UserProfile: Codable {
    var userId: String
    var username: String?
    var callName: String?
    var email: String?
    var emergencyContact: EmergencyContact?
    var emergencyContact2: EmergencyContact?
    var lastCheckinDate: String?
    var lastAlertAt: String?
    var language: String?
}

struct AuthUser: Codable {
    var userId: String
    var username: String?
    var callName: String?
    var email: String?
    var emergencyContact: EmergencyContact?
    var emergencyContact2: EmergencyContact?
    var language: String?
}

struct APIResponse<T: Codable>: Codable {
    var ok: Bool
    var message: String?
    var user: T?
    var triggered: Bool?
    var emergencyShouldTrigger: Bool?
}

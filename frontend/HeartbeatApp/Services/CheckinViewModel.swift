import Foundation
import CoreMotion

@MainActor
final class CheckinViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var callName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""

    @Published var isAuthenticated: Bool = false {
        didSet {
            if isAuthenticated && autoCheckinBySteps {
                startPedometerUpdates()
            } else if !isAuthenticated {
                stopPedometerUpdates()
            }
        }
    }
    @Published var hasCompletedEmergencySetup: Bool = false

    @Published var checkinDays: Int = 0
    @Published var selectedLanguage: String = "English"
    @Published var statusText: String = ""
    @Published var isLoading: Bool = false
    @Published var autoCheckinBySteps: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCheckinBySteps, forKey: "autoCheckinBySteps")
            if autoCheckinBySteps && isAuthenticated {
                startPedometerUpdates()
            } else {
                stopPedometerUpdates()
            }
        }
    }
    @Published var autoCheckinByUnlock: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCheckinByUnlock, forKey: "autoCheckinByUnlock")
        }
    }
    @Published var dailyReminderEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(dailyReminderEnabled, forKey: "dailyReminderEnabled")
        }
    }
    @Published var dailyReminderTime: Date = CheckinViewModel.defaultReminderTime {
        didSet {
            UserDefaults.standard.set(dailyReminderTime.timeIntervalSince1970, forKey: "dailyReminderTime")
        }
    }
    @Published var contactName: String = ""
    @Published var contactPhone: String = ""
    @Published var contactName2: String = ""
    @Published var contactPhone2: String = ""
    @Published var baseURL: String = CheckinViewModel.resolveBaseURL()

    private let api = APIClient()
    private var userId = "ios-local-user"
    private var lastCheckinDate: Date?
    private let pedometer = CMPedometer()

    private static var defaultReminderTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Resolve API base URL with a clear dev/prod fallback order:
    /// 1) Info.plist `API_BASE_URL` (preferred for release builds)
    /// 2) Debug fallback localhost
    /// 3) Production placeholder (must be replaced before release)
    private static func resolveBaseURL() -> String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        #if DEBUG
        return "http://127.0.0.1:4000"
        #else
        return "https://your-railway-domain.up.railway.app"
        #endif
    }
    
    init() {
        self.autoCheckinBySteps = UserDefaults.standard.bool(forKey: "autoCheckinBySteps")
        self.autoCheckinByUnlock = UserDefaults.standard.bool(forKey: "autoCheckinByUnlock")
        self.dailyReminderEnabled = UserDefaults.standard.bool(forKey: "dailyReminderEnabled")

        let storedReminderTimestamp = UserDefaults.standard.double(forKey: "dailyReminderTime")
        if storedReminderTimestamp > 0 {
            self.dailyReminderTime = Date(timeIntervalSince1970: storedReminderTimestamp)
        } else {
            self.dailyReminderTime = Self.defaultReminderTime
        }
        
        // Only start if authenticated (initially false, but just in case logic changes)
        if autoCheckinBySteps && isAuthenticated {
            startPedometerUpdates()
        }
    }

    /// Returns "en" or "zh" based on the device language.
    var deviceLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("zh") ? "zh" : "en"
    }

    private struct RegisterBody: Codable {
        let userId: String
        let emergencyContact: EmergencyContact
        let emergencyContact2: EmergencyContact?
        let callName: String
    }

    private struct CheckinBody: Codable {
        let userId: String
    }

    private struct AuthRegisterBody: Codable {
        let username: String
        let email: String
        let password: String
        let language: String
    }

    private struct AuthLoginBody: Codable {
        let email: String
        let password: String
        let language: String
    }

    private struct SendCodeBody: Codable {
        let email: String
        let language: String
    }

    private struct ResetPasswordBody: Codable {
        let email: String
        let code: String
        let newPassword: String
        let language: String
    }

    private struct ChangePasswordBody: Codable {
        let email: String
        let currentPassword: String
        let newPassword: String
        let language: String
    }

    private struct UpdateCallNameBody: Codable {
        let userId: String
        let callName: String
    }

    func registerOrLogin() async {
        isLoading = true
        defer { isLoading = false }

        let trimmedName = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            statusText = String(localized: "Enter your username")
            return
        }
        guard !trimmedEmail.isEmpty else {
            statusText = String(localized: "Enter your email")
            return
        }
        guard !password.isEmpty else {
            statusText = String(localized: "Enter your password")
            return
        }
        guard password == confirmPassword else {
            statusText = String(localized: "Passwords do not match")
            return
        }

        do {
            let body = AuthRegisterBody(username: trimmedName, email: trimmedEmail, password: password, language: deviceLanguage)
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/register",
                method: "POST",
                body: body,
                responseType: APIResponse<AuthUser>.self
            )
            if response.ok, let user = response.user {
                userId = user.userId
                username = user.username ?? trimmedName
                callName = user.callName ?? user.username ?? trimmedName
                isAuthenticated = true
                statusText = response.message ?? ""
                
                // Parse optional fields
                if let contact = user.emergencyContact {
                    contactName = contact.name ?? ""
                    contactPhone = contact.phone ?? ""
                }
                if let contact2 = user.emergencyContact2 {
                    contactName2 = contact2.name ?? ""
                    contactPhone2 = contact2.phone ?? ""
                }
                selectedLanguage = user.language ?? "en"
                hasCompletedEmergencySetup = !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
            } else {
                statusText = response.message ?? ""
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    func login() async {
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty else {
            statusText = String(localized: "Enter your email")
            return
        }
        guard !password.isEmpty else {
            statusText = String(localized: "Enter your password")
            return
        }

        do {
            let body = AuthLoginBody(email: trimmedEmail, password: password, language: deviceLanguage)
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/login",
                method: "POST",
                body: body,
                responseType: APIResponse<AuthUser>.self
            )
            if response.ok, let user = response.user {
                userId = user.userId
                username = user.username ?? trimmedEmail.split(separator: "@").first.map(String.init) ?? trimmedEmail
                callName = user.callName ?? user.username ?? username
                email = user.email ?? trimmedEmail
                isAuthenticated = true
                statusText = response.message ?? ""
                
                // Parse optional fields
                if let contact = user.emergencyContact {
                    contactName = contact.name ?? ""
                    contactPhone = contact.phone ?? ""
                }
                if let contact2 = user.emergencyContact2 {
                    contactName2 = contact2.name ?? ""
                    contactPhone2 = contact2.phone ?? ""
                }
                selectedLanguage = user.language ?? "en"
                hasCompletedEmergencySetup = !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
            } else {
                statusText = response.message ?? ""
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    func continueWithAppleID() {
        if username.trimmingCharacters(in: .whitespaces).isEmpty {
            username = "Apple User"
        }
        if email.trimmingCharacters(in: .whitespaces).isEmpty {
            email = "appleid@example.com"
        }

        userId = "ios-apple-user"
        isAuthenticated = true
        statusText = ""
    }

    func logout() {
        isAuthenticated = false
        hasCompletedEmergencySetup = false
        callName = ""
        password = ""
        confirmPassword = ""
        lastCheckinDate = nil
        statusText = ""
    }

    func updateLanguage(to language: String) {
        selectedLanguage = language
    }

    func sendVerificationCode(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/send-code",
                method: "POST",
                body: SendCodeBody(email: email, language: deviceLanguage),
                responseType: APIResponse<AuthUser>.self
            )
            statusText = response.message ?? ""
            return response.ok
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func resetPassword(email: String, code: String, newPassword: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let body = ResetPasswordBody(email: email, code: code, newPassword: newPassword, language: deviceLanguage)
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/reset-password",
                method: "POST",
                body: body,
                responseType: APIResponse<AuthUser>.self
            )
            statusText = response.message ?? ""
            return response.ok
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        guard newPassword.count >= 6 else {
            statusText = String(localized: "Password must be at least 6 characters")
            return false
        }
        do {
            let body = ChangePasswordBody(email: email, currentPassword: currentPassword, newPassword: newPassword, language: deviceLanguage)
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/change-password",
                method: "POST",
                body: body,
                responseType: APIResponse<AuthUser>.self
            )
            statusText = response.message ?? ""
            return response.ok
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func updateCallName(_ value: String) async -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = String(localized: "Call name cannot be empty")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/user/call-name",
                method: "POST",
                body: UpdateCallNameBody(userId: userId, callName: trimmed),
                responseType: APIResponse<UserProfile>.self
            )

            if response.ok {
                callName = response.user?.callName ?? trimmed
                statusText = response.message ?? ""
                return true
            }

            statusText = response.message ?? String(localized: "Failed to update call name")
            return false
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func registerUser() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        guard !contactName.trimmingCharacters(in: .whitespaces).isEmpty,
              !contactPhone.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusText = String(localized: "We recommend adding at least one emergency contact so your loved ones can be reached in an emergency.")
            return false
        }

        let body = RegisterBody(
            userId: userId,
            emergencyContact: EmergencyContact(name: contactName, phone: contactPhone),
            emergencyContact2: (!contactName2.trimmingCharacters(in: .whitespaces).isEmpty || !contactPhone2.trimmingCharacters(in: .whitespaces).isEmpty)
                ? EmergencyContact(name: contactName2, phone: contactPhone2)
                : nil,
            callName: callName.trimmingCharacters(in: .whitespaces).isEmpty ? username : callName
        )

        do {
            let _: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/user/register",
                method: "POST",
                body: body,
                responseType: APIResponse<UserProfile>.self
            )
            hasCompletedEmergencySetup = true
            statusText = ""
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func checkInToday() async {
        isLoading = true
        defer { isLoading = false }

        guard !hasCheckedInToday else {
            statusText = String(localized: "Checked in today ✓")
            return
        }

        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/checkin",
                method: "POST",
                body: CheckinBody(userId: userId),
                responseType: APIResponse<UserProfile>.self
            )
            checkinDays += 1
            lastCheckinDate = Date()
            statusText = response.message ?? ""
        } catch {
            statusText = error.localizedDescription
        }
    }

    func triggerAutoCheckinFromUI() async {
        guard autoCheckinBySteps || autoCheckinByUnlock else {
            statusText = String(localized: "Please enable auto check-in in settings")
            return
        }

        if hasCheckedInToday {
            statusText = String(localized: "Checked in today ✓")
            return
        }

        await checkInToday()
    }

    func handleStepCountUpdate(_ steps: Int) async {
        guard autoCheckinBySteps, steps >= 100, !hasCheckedInToday else { return }
        statusText = String(format: String(localized: "Daily steps reached %lld, auto checking in"), steps)
        await checkInToday()
    }

    func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else {
            statusText = String(localized: "Step counting not available on this device/simulator")
            return
        }
        
        // Start from midnight
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        
        statusText = String(localized: "Requesting step tracking permission...")
        
        pedometer.startUpdates(from: midnight) { [weak self] data, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.statusText = String(format: String(localized: "Step tracking error: %@"), error.localizedDescription)
                }
                return
            }
            guard let data else { return }
            DispatchQueue.main.async {
                Task {
                    await self.handleStepCountUpdate(data.numberOfSteps.intValue)
                }
            }
        }
    }

    func stopPedometerUpdates() {
        pedometer.stopUpdates()
    }

    func handleAppUnlockEvent() async {
        guard autoCheckinByUnlock, !hasCheckedInToday else { return }
        statusText = String(localized: "Device unlock detected, auto checking in")
        await checkInToday()
    }

    var hasCheckedInToday: Bool {
        guard let lastCheckinDate else { return false }
        return Calendar.current.isDateInToday(lastCheckinDate)
    }

    func evaluateEmergency() async {
        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/evaluate",
                method: "POST",
                body: CheckinBody(userId: userId),
                responseType: APIResponse<UserProfile>.self
            )
            if response.triggered == true {
                statusText = String(localized: "Emergency contact triggered (Backend simulation)")
            } else {
                statusText = response.message ?? String(localized: "Emergency contact not needed at this time")
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    func loadStatus() async {
        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/status/\(userId)",
                method: "GET",
                body: Optional<String>.none,
                responseType: APIResponse<UserProfile>.self
            )

            if let user = response.user {
                callName = user.callName ?? user.username ?? callName
                if let contact = user.emergencyContact {
                    contactName = contact.name ?? ""
                    contactPhone = contact.phone ?? ""
                }
                if let contact2 = user.emergencyContact2 {
                    contactName2 = contact2.name ?? ""
                    contactPhone2 = contact2.phone ?? ""
                }
                selectedLanguage = user.language ?? "en"
                hasCompletedEmergencySetup = !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if response.emergencyShouldTrigger == true {
                statusText = String(localized: "Warning: Not checked in for over 2 days")
            }
        } catch {
            // First launch may not have registered user yet; keep default hint.
        }
    }
}

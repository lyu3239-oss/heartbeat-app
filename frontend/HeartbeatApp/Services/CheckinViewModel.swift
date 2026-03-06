import Foundation
import CoreMotion
import UserNotifications

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
            UserDefaults.standard.set(autoCheckinBySteps, forKey: autoCheckinByStepsKey)
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
            Task { await refreshDailyReminderScheduleIfNeeded() }
        }
    }
    @Published var dailyReminderTime: Date = CheckinViewModel.defaultReminderTime {
        didSet {
            UserDefaults.standard.set(dailyReminderTime.timeIntervalSince1970, forKey: "dailyReminderTime")
            guard dailyReminderEnabled else { return }
            Task { await scheduleDailyReminder() }
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
    private let dailyReminderRequestId = "heartbeat.daily-reminder"

    /// Number of days since last check-in (nil if never checked in)
    @Published var daysSinceLastCheckin: Int?

    private static var defaultReminderTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private var autoCheckinByStepsKey: String {
        "autoCheckinBySteps_\(userId)"
    }

    /// Resolve API base URL with a clear dev/prod fallback order:
    /// 1) Info.plist `API_BASE_URL` (required for release builds)
    /// 2) Debug fallback localhost
    private static func resolveBaseURL() -> String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("your-railway-domain") {
                return trimmed
            }
        }

        #if DEBUG
        return "http://127.0.0.1:4000"
        #else
        fatalError("API_BASE_URL must be configured in Info.plist for release builds")
        #endif
    }
    
    init() {
        // Keep default OFF until a specific user signs in and preferences are loaded.
        self.autoCheckinBySteps = false
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

        // Set up session expiration callback
        api.onSessionExpired = { [weak self] in
            Task { @MainActor in
                self?.logout()
            }
        }

        Task { await refreshDailyReminderScheduleIfNeeded() }
    }

    private func refreshDailyReminderScheduleIfNeeded() async {
        if dailyReminderEnabled {
            await scheduleDailyReminder()
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderRequestId])
        }
    }

    private func scheduleDailyReminder() async {
        let center = UNUserNotificationCenter.current()
        let hasPermission = await ensureNotificationAuthorization(center: center)

        guard hasPermission else {
            dailyReminderEnabled = false
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderRequestId])

        var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: dailyReminderTime)
        dateComponents.second = 0

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Daily Check-in Reminder")
        content.body = String(localized: "It's time to check in today")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: dailyReminderRequestId, content: content, trigger: trigger)

        do {
            try await addNotificationRequest(request, center: center)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func ensureNotificationAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                statusText = error.localizedDescription
                return false
            }
        case .denied:
            statusText = String(localized: "Notifications are disabled. Please enable notifications in Settings.")
            return false
        @unknown default:
            return false
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func loadUserAutoCheckinPreference() {
        // `bool(forKey:)` defaults to false when key doesn't exist, matching product requirement.
        autoCheckinBySteps = UserDefaults.standard.bool(forKey: autoCheckinByStepsKey)
    }

    /// Returns "en" or "zh" based on the device language.
    var deviceLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("zh") ? "zh" : "en"
    }

    private struct RegisterBody: Codable {
        let emergencyContact: EmergencyContact
        let emergencyContact2: EmergencyContact?
        let callName: String
    }

    private struct EmptyBody: Codable {}

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

    private struct DeleteAccountBody: Codable {
        let email: String
        let password: String
        let language: String
    }

    private struct UpdateCallNameBody: Codable {
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
        guard password.count >= 6 else {
            statusText = String(localized: "Password must be at least 6 characters")
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
                loadUserAutoCheckinPreference()
                username = user.username ?? trimmedName
                callName = user.callName ?? user.username ?? trimmedName
                email = user.email ?? trimmedEmail

                // Save JWT tokens to Keychain
                if let accessToken = response.accessToken {
                    KeychainService.save(key: .accessToken, value: accessToken)
                }
                if let refreshToken = response.refreshToken {
                    KeychainService.save(key: .refreshToken, value: refreshToken)
                }
                KeychainService.save(key: .userId, value: userId)
                KeychainService.save(key: .userEmail, value: email)

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
        guard password.count >= 6 else {
            statusText = String(localized: "Password must be at least 6 characters")
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
                loadUserAutoCheckinPreference()
                username = user.username ?? trimmedEmail.split(separator: "@").first.map(String.init) ?? trimmedEmail
                callName = user.callName ?? user.username ?? username
                email = user.email ?? trimmedEmail

                // Save JWT tokens to Keychain
                if let accessToken = response.accessToken {
                    KeychainService.save(key: .accessToken, value: accessToken)
                }
                if let refreshToken = response.refreshToken {
                    KeychainService.save(key: .refreshToken, value: refreshToken)
                }
                KeychainService.save(key: .userId, value: userId)
                KeychainService.save(key: .userEmail, value: email)

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

    // MARK: - Apple Sign In (Not Implemented)
    // This function is not currently used in the UI and should not be called
    // To implement properly, integrate AuthenticationServices framework
    /*
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
    */

    func logout() {
        KeychainService.deleteAll()
        isAuthenticated = false
        hasCompletedEmergencySetup = false
        username = ""
        email = ""
        callName = ""
        contactName = ""
        contactPhone = ""
        contactName2 = ""
        contactPhone2 = ""
        password = ""
        confirmPassword = ""
        checkinDays = 0
        lastCheckinDate = nil
        daysSinceLastCheckin = nil
        statusText = ""
    }

    /// Restore session from Keychain on app launch
    func restoreSession() async {
        guard let storedUserId = KeychainService.get(key: .userId),
              let storedEmail = KeychainService.get(key: .userEmail),
              KeychainService.get(key: .accessToken) != nil else {
            return
        }

        userId = storedUserId
        email = storedEmail
        loadUserAutoCheckinPreference()

        // Verify session by calling /api/status
        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/status/\(userId)",
                method: "GET",
                body: Optional<String>.none,
                responseType: APIResponse<UserProfile>.self,
                authenticated: true
            )

            if let user = response.user {
                username = user.username ?? email.split(separator: "@").first.map(String.init) ?? email
                callName = user.callName ?? user.username ?? username
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

                // Calculate days since last check-in
                if let lastCheckinDateStr = user.lastCheckinDate {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    if let lastDate = formatter.date(from: lastCheckinDateStr) {
                        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
                        daysSinceLastCheckin = days
                    }
                }

                isAuthenticated = true
            }
        } catch {
            // Session invalid - clear tokens
            KeychainService.deleteAll()
        }
    }

    func deleteAccount(currentPassword: String) async -> Bool {
        let trimmedPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = String(localized: "Missing account email")
            return false
        }
        guard !trimmedPassword.isEmpty else {
            statusText = String(localized: "Enter your password to delete account")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<AuthUser> = try await api.request(
                baseURL: baseURL,
                path: "/api/auth/delete-account",
                method: "POST",
                body: DeleteAccountBody(email: email, password: trimmedPassword, language: deviceLanguage),
                responseType: APIResponse<AuthUser>.self,
                authenticated: true
            )

            if response.ok {
                KeychainService.deleteAll()
                logout()
                statusText = response.message ?? String(localized: "Account deleted")
                return true
            }

            statusText = response.message ?? String(localized: "Failed to delete account")
            return false
        } catch {
            statusText = error.localizedDescription
            return false
        }
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
                body: UpdateCallNameBody(callName: trimmed),
                responseType: APIResponse<UserProfile>.self,
                authenticated: true
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
                responseType: APIResponse<UserProfile>.self,
                authenticated: true
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
                body: EmptyBody(),
                responseType: APIResponse<UserProfile>.self,
                authenticated: true
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

    func loadStatus() async {
        do {
            let response: APIResponse<UserProfile> = try await api.request(
                baseURL: baseURL,
                path: "/api/status/\(userId)",
                method: "GET",
                body: Optional<String>.none,
                responseType: APIResponse<UserProfile>.self,
                authenticated: true
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

                // Calculate days since last check-in
                if let lastCheckinDateStr = user.lastCheckinDate {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    if let lastDate = formatter.date(from: lastCheckinDateStr) {
                        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
                        daysSinceLastCheckin = days
                        if days == 0 {
                            lastCheckinDate = lastDate
                        }
                    }
                } else {
                    daysSinceLastCheckin = nil
                }
            }
        } catch {
            // First launch may not have registered user yet; keep default hint.
        }
    }
}

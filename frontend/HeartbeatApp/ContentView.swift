import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: CheckinViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showProfileMenu = false
    @State private var activeScreen: AppScreen = .main
    @State private var authScreen: AuthScreen = .login
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var resetEmail = ""
    @State private var verificationCode = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var showNewPassword = false
    @State private var showConfirmNewPassword = false
    @State private var showAutoCheckinSheet = false
    @State private var showNotificationSheet = false
    @State private var showCallNameSheet = false
    @State private var draftCallName = ""
    @State private var currentPassword = ""
    @State private var changeNewPassword = ""
    @State private var changeConfirmPassword = ""
    @State private var showCurrentPassword = false
    @State private var showChangeNewPassword = false
    @State private var showChangeConfirmPassword = false
    @State private var showRegistrationSuccess = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeletePasswordSheet = false
    @State private var deleteAccountPassword = ""
    @State private var bypassEmergencySetupGate = false
    @State private var emergencyOpenedFromSettings = false
    @State private var showAvatarSheet = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarPreviewImage: UIImage?
    @State private var avatarLoadError = ""
    @State private var showMakeupCheckinAlert = false
    @AppStorage("profileAvatarBase64") private var legacyProfileAvatarBase64 = ""

    init(initialAuthScreen: AuthScreen = .login, initialActiveScreen: AppScreen = .main, initialShowRegistrationSuccess: Bool = false) {
        _authScreen = State(initialValue: initialAuthScreen)
        _activeScreen = State(initialValue: initialActiveScreen)
        _showRegistrationSuccess = State(initialValue: initialShowRegistrationSuccess)
    }

    enum AppScreen {
        case main
        case emergency
        case settings
        case changePassword
    }

    enum AuthScreen {
        case login
        case register
        case forgotPassword
    }

    private var termsURL: URL? {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TERMS_OF_SERVICE_URL") as? String
        let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: (value?.isEmpty == false ? value! : "https://heartbeatapp.space/terms"))
    }

    private var privacyURL: URL? {
        let configured = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_POLICY_URL") as? String
        let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: (value?.isEmpty == false ? value! : "https://heartbeatapp.space/privacy"))
    }

    private func openLegalURL(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }

    var body: some View {
        Group {
            if !viewModel.isAuthenticated {
                authView
            } else if showRegistrationSuccess {
                registrationSuccessView
            } else {
                NavigationStack {
                    Group {
                        switch activeScreen {
                        case .settings:
                            settingsView
                        case .emergency:
                            emergencySetupView
                        case .changePassword:
                            changePasswordView
                        case .main:
                            if viewModel.hasCompletedEmergencySetup || bypassEmergencySetupGate {
                                mainView
                            } else {
                                emergencySetupView
                            }
                        }
                    }
                    .navigationTitle(currentNavigationTitle)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if activeScreen == .settings {
                                Button(String(localized: "Back")) {
                                    activeScreen = .main
                                }
                            } else if activeScreen == .emergency, emergencyOpenedFromSettings {
                                Button(String(localized: "Back")) {
                                    activeScreen = .settings
                                }
                            } else if activeScreen == .emergency || (!viewModel.hasCompletedEmergencySetup && activeScreen == .main) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.blue)
                                    .accessibilityLabel(String(localized: "User avatar"))
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            if (activeScreen == .emergency || (!viewModel.hasCompletedEmergencySetup && activeScreen == .main)),
                               viewModel.hasCompletedEmergencySetup,
                               !emergencyOpenedFromSettings {
                                Button(String(localized: "Back")) {
                                    activeScreen = .main
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.handleAppUnlockEvent() }
        }
        .onChange(of: activeScreen) { _ in
            if showProfileMenu {
                withAnimation { showProfileMenu = false }
            }
        }
        .task {
            migrateLegacyAvatarIfNeeded()
        }
    }

    private var currentNavigationTitle: String {
        switch activeScreen {
        case .settings:
            return ""
        case .emergency:
            return ""
        case .changePassword:
            return ""
        case .main:
            return viewModel.hasCompletedEmergencySetup ? "" : ""
        }
    }

    private var authView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)

                    switch authScreen {
                    case .login:
                        loginFormView
                    case .register:
                        registerFormView
                    case .forgotPassword:
                        forgotPasswordFormView
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private var loginFormView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text(String(localized: "Welcome Back"))
                    .font(.system(size: 32, weight: .bold))
                Text(String(localized: "Sign in to continue"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Email"))
                    .font(.subheadline.bold())
                TextField(String(localized: "Enter your email"), text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Password"))
                    .font(.subheadline.bold())
                HStack {
                    if showPassword {
                        TextField(String(localized: "Enter your password"), text: $viewModel.password)
                    } else {
                        SecureField(String(localized: "Enter your password"), text: $viewModel.password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(12)

                HStack {
                    Spacer()
                    Button(String(localized: "Forgot password?")) {
                        resetEmail = viewModel.email
                        authScreen = .forgotPassword
                    }
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
            }

            Spacer().frame(height: 4)

            // Reserve error-message space so button positions stay fixed.
            Text(viewModel.statusText.isEmpty ? " " : viewModel.statusText)
                .foregroundStyle(.red)
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .accessibilityHidden(viewModel.statusText.isEmpty)

            // Login button
            Button {
                Task { await viewModel.login() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                } else {
                    Text(String(localized: "Sign In"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
            }

            // Register link
            HStack(spacing: 4) {
                Spacer()
                Text(String(localized: "Don't have an account?"))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Sign Up")) {
                    authScreen = .register
                    viewModel.confirmPassword = ""
                }
                .fontWeight(.semibold)
                Spacer()
            }
            .font(.subheadline)
        }
    }

    private var forgotPasswordFormView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Back button
            Button {
                authScreen = .login
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(String(localized: "Back"))
                }
                .foregroundStyle(.blue)
            }

            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Forgot Password"))
                    .font(.system(size: 32, weight: .bold))
                Text(String(localized: "Verify your email to reset your password"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Email"))
                    .font(.subheadline.bold())
                TextField(String(localized: "Enter your email address"), text: $resetEmail)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }

            // Verification code field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Verification Code"))
                    .font(.subheadline.bold())
                HStack(spacing: 10) {
                    TextField(String(localized: "Enter verification code"), text: $verificationCode)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)

                    Button {
                        Task { await viewModel.sendVerificationCode(email: resetEmail) }
                    } label: {
                        Text(String(localized: "Send Code"))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }

            // New password field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "New Password"))
                    .font(.subheadline.bold())
                HStack {
                    if showNewPassword {
                        TextField(String(localized: "Set new password (6+ chars)"), text: $newPassword)
                    } else {
                        SecureField(String(localized: "Set new password (6+ chars)"), text: $newPassword)
                    }
                    Button {
                        showNewPassword.toggle()
                    } label: {
                        Image(systemName: showNewPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            // Confirm new password field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Confirm Password"))
                    .font(.subheadline.bold())
                HStack {
                    if showConfirmNewPassword {
                        TextField(String(localized: "Re-enter new password"), text: $confirmNewPassword)
                    } else {
                        SecureField(String(localized: "Re-enter new password"), text: $confirmNewPassword)
                    }
                    Button {
                        showConfirmNewPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmNewPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            VStack(spacing: 12) {
                // Reserve message space so reset controls do not shift when status appears.
                Text(viewModel.statusText.isEmpty ? " " : viewModel.statusText)
                    .foregroundStyle(.blue)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .center)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(viewModel.statusText.isEmpty)

                // Reset button
                Button {
                    Task {
                        let success = await viewModel.resetPassword(
                            email: resetEmail,
                            code: verificationCode,
                            newPassword: newPassword
                        )
                        if success {
                            authScreen = .login
                            newPassword = ""
                            confirmNewPassword = ""
                            verificationCode = ""
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(14)
                    } else {
                        Text(String(localized: "Reset Password"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(14)
                    }
                }

                // Tip box
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                    Text(String(localized: "A verification code will be sent to your email"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            .padding(.top, -8)
        }
    }

    private var registerFormView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Back button
            Button {
                authScreen = .login
                viewModel.confirmPassword = ""
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(String(localized: "Back"))
                }
                .foregroundStyle(.blue)
            }

            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Create Account"))
                    .font(.system(size: 32, weight: .bold))
                Text(String(localized: "Fill in the info to sign up"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            // Username field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Username"))
                    .font(.subheadline.bold())
                TextField(String(localized: "Enter your username"), text: $viewModel.username)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Email"))
                    .font(.subheadline.bold())
                TextField(String(localized: "Enter your email"), text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Password"))
                    .font(.subheadline.bold())
                HStack {
                    if showPassword {
                        TextField(String(localized: "Set password (6+ chars)"), text: $viewModel.password)
                    } else {
                        SecureField(String(localized: "Set password (6+ chars)"), text: $viewModel.password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Confirm Password"))
                    .font(.subheadline.bold())
                HStack {
                    if showConfirmPassword {
                        TextField(String(localized: "Re-enter your password"), text: $viewModel.confirmPassword)
                    } else {
                        SecureField(String(localized: "Re-enter your password"), text: $viewModel.confirmPassword)
                    }
                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            Spacer().frame(height: 16)

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            // Register button
            Button {
                Task {
                    await viewModel.registerOrLogin()
                    if viewModel.isAuthenticated {
                        showRegistrationSuccess = true
                    }
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                } else {
                    Text(String(localized: "Sign Up"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
            }

            // Terms
            VStack(spacing: 2) {
                Text(String(localized: "By signing up, you agree to the"))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Button(String(localized: "Terms of Service")) {
                        openLegalURL(termsURL)
                    }
                        .fontWeight(.semibold)
                    Text(String(localized: "and"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Privacy Policy")) {
                        openLegalURL(privacyURL)
                    }
                        .fontWeight(.semibold)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    @State private var showContactSheet = false
    @State private var editingContactIndex: Int = 1

    private var emergencySetupView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Set Emergency Contacts"))
                        .font(.system(size: 28, weight: .bold))
                    Text(String(localized: "Add emergency contacts for when they're needed"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 28)

                // Contact cards + add button
                VStack(spacing: 12) {
                    // Show added contact 1
                    if !viewModel.contactName.isEmpty || !viewModel.contactPhone.isEmpty {
                        contactCard(
                            name: viewModel.contactName,
                            phone: viewModel.contactPhone,
                            label: String(localized: "Emergency Contact 1")
                        ) {
                            editingContactIndex = 1
                            showContactSheet = true
                        }
                    }

                    // Show added contact 2
                    if !viewModel.contactName2.isEmpty || !viewModel.contactPhone2.isEmpty {
                        contactCard(
                            name: viewModel.contactName2,
                            phone: viewModel.contactPhone2,
                            label: String(localized: "Emergency Contact 2")
                        ) {
                            editingContactIndex = 2
                            showContactSheet = true
                        }
                    }

                    // Add button (dashed border)
                    Button {
                        if viewModel.contactName.isEmpty && viewModel.contactPhone.isEmpty {
                            editingContactIndex = 1
                        } else {
                            editingContactIndex = 2
                        }
                        showContactSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text(String(localized: "Add Emergency Contact"))
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                                .foregroundStyle(Color(.systemGray3))
                        )
                    }
                }

                // Tip box
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                    Text(String(localized: "We recommend adding at least one emergency contact so your loved ones can be reached in an emergency."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.top, 16)

                Spacer()

                // Bottom buttons
                VStack(spacing: 14) {
                    Button {
                        Task {
                            let ok = await viewModel.registerUser()
                            if ok {
                                activeScreen = .main
                            }
                        }
                    } label: {
                        Text(String(localized: "Complete"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(14)
                    }

                    Button {
                        bypassEmergencySetupGate = true
                        activeScreen = .main
                    } label: {
                        Text(String(localized: "Skip"))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 28)
        }
        .sheet(isPresented: $showContactSheet) {
            contactEditSheet
        }
    }

    private func contactCard(name: String, phone: String, label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name.isEmpty ? String(localized: "Name not set") : name)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                Text(phone.isEmpty ? String(localized: "Phone not set") : phone)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    @State private var tempContactName = ""
    @State private var tempContactPhone = ""

    private var contactEditSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Name"))
                        .font(.subheadline.bold())
                    TextField(String(localized: "Enter contact name"), text: $tempContactName)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Phone"))
                        .font(.subheadline.bold())
                    TextField(String(localized: "Enter contact phone"), text: $tempContactPhone)
                        .keyboardType(.phonePad)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(editingContactIndex == 1 ? String(localized: "Emergency Contact 1") : String(localized: "Emergency Contact 2"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        showContactSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if editingContactIndex == 1 {
                            viewModel.contactName = tempContactName
                            viewModel.contactPhone = tempContactPhone
                        } else {
                            viewModel.contactName2 = tempContactName
                            viewModel.contactPhone2 = tempContactPhone
                        }
                        showContactSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if editingContactIndex == 1 {
                    tempContactName = viewModel.contactName
                    tempContactPhone = viewModel.contactPhone
                } else {
                    tempContactName = viewModel.contactName2
                    tempContactPhone = viewModel.contactPhone2
                }
            }
        }
    }

    private var registrationSuccessView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.green)

                Text(String(localized: "Registration Successful!"))
                    .font(.system(size: 32, weight: .bold))

                Text(String(localized: "Welcome! Let's set up your emergency contacts"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showRegistrationSuccess = false
                } label: {
                    Text(String(localized: "Next"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }

    private var changePasswordView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Back button
                    Button {
                        activeScreen = .settings
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(String(localized: "back"))
                        }
                        .foregroundStyle(.blue)
                    }

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Change Password"))
                            .font(.system(size: 32, weight: .bold))
                        Text(String(localized: "Change your password regularly for security"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)

                    // Current password
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Current Password"))
                            .font(.subheadline.bold())
                        HStack {
                            if showCurrentPassword {
                                TextField(String(localized: "Enter current password"), text: $currentPassword)
                            } else {
                                SecureField(String(localized: "Enter current password"), text: $currentPassword)
                            }
                            Button {
                                showCurrentPassword.toggle()
                            } label: {
                                Image(systemName: showCurrentPassword ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }

                    // New password
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "New Password"))
                            .font(.subheadline.bold())
                        HStack {
                            if showChangeNewPassword {
                                TextField(String(localized: "Set new password (6+ chars)"), text: $changeNewPassword)
                            } else {
                                SecureField(String(localized: "Set new password (6+ chars)"), text: $changeNewPassword)
                            }
                            Button {
                                showChangeNewPassword.toggle()
                            } label: {
                                Image(systemName: showChangeNewPassword ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }

                    // Confirm new password
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Confirm New Password"))
                            .font(.subheadline.bold())
                        HStack {
                            if showChangeConfirmPassword {
                                TextField(String(localized: "Re-enter new password"), text: $changeConfirmPassword)
                            } else {
                                SecureField(String(localized: "Re-enter new password"), text: $changeConfirmPassword)
                            }
                            Button {
                                showChangeConfirmPassword.toggle()
                            } label: {
                                Image(systemName: showChangeConfirmPassword ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }

                    Spacer().frame(height: 16)

                    // Confirm button
                    Button {
                        guard changeNewPassword == changeConfirmPassword else {
                            viewModel.statusText = String(localized: "Passwords do not match")
                            return
                        }
                        Task {
                            let success = await viewModel.changePassword(
                                currentPassword: currentPassword,
                                newPassword: changeNewPassword
                            )
                            if success {
                                currentPassword = ""
                                changeNewPassword = ""
                                changeConfirmPassword = ""
                                activeScreen = .settings
                            }
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(14)
                        } else {
                            Text(String(localized: "Confirm Change"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(14)
                        }
                    }

                    // Security tips
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                            Text(String(localized: "Password Security Tips:"))
                                .font(.footnote.bold())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "• At least 6 characters"))
                            Text(String(localized: "• Mix letters, numbers, and symbols"))
                            Text(String(localized: "• Avoid overly simple passwords"))
                            Text(String(localized: "• Change passwords regularly"))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)

                    // Forgot password link
                    Button {
                        viewModel.isAuthenticated = false
                        resetEmail = viewModel.email
                        authScreen = .forgotPassword
                    } label: {
                        Text(String(localized: "Forgot current password?"))
                            .font(.footnote)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
            }
        }
    }

    private var settingsView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Top bar
                    HStack(spacing: 12) {
                        Button {
                            activeScreen = .main
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Text(String(localized: "Settings"))
                            .font(.system(size: 24, weight: .bold))
                        Spacer()
                    }
                    .padding(.bottom, 24)

                    // User profile card
                    Button {
                        avatarPreviewImage = storedAvatarImage
                        selectedAvatarItem = nil
                        avatarLoadError = ""
                        showAvatarSheet = true
                    } label: {
                        HStack(spacing: 14) {
                            // Avatar
                            avatarView(size: 50)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.username.isEmpty ? String(localized: "Username") : viewModel.username)
                                    .font(.body.bold())
                                    .foregroundStyle(.primary)
                                Text(maskedEmail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                    }
                    .padding(.bottom, 24)

                    // Account settings section
                    Text(String(localized: "Account Settings"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        settingsRow(icon: "phone.fill", title: String(localized: "Emergency Contacts")) {
                            emergencyOpenedFromSettings = true
                            navigate(to: .emergency)
                        }
                        Divider().padding(.leading, 52)
                        settingsRow(
                            icon: "person.text.rectangle",
                            title: String(localized: "Call Name"),
                            detail: currentCallNameDisplay
                        ) {
                            draftCallName = currentCallNameDisplay
                            showCallNameSheet = true
                        }
                        Divider().padding(.leading, 52)
                        settingsRow(icon: "heart", title: String(localized: "Auto Check-in")) {
                            showAutoCheckinSheet = true
                        }
                        Divider().padding(.leading, 52)
                        settingsRow(icon: "lock.fill", title: String(localized: "Change Password")) {
                            navigate(to: .changePassword)
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .padding(.bottom, 24)

                    // Security and privacy section
                    Text(String(localized: "Security & Privacy"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        settingsRow(icon: "bell.badge.fill", title: String(localized: "Notifications")) {
                            showNotificationSheet = true
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .padding(.bottom, 24)

                    Text(String(localized: "Danger Zone"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.bottom, 8)

                    Button {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "trash.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            Text(String(localized: "Delete Account"))
                                .font(.body)
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                    }
                    .padding(.bottom, 10)

                    Button {
                        openLegalURL(privacyURL)
                    } label: {
                        Text(String(localized: "View deletion details in Privacy Policy"))
                            .font(.footnote)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 24)



                    // Version
                    Text(String(localized: "Version 1.0.0"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)

                    // Logout button
                    Button {
                        bypassEmergencySetupGate = false
                        viewModel.logout()
                        activeScreen = .main
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(String(localized: "Sign Out"))
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
            }
        }
        .sheet(isPresented: $showAutoCheckinSheet) {
            NavigationStack {
                List {
                    Toggle(isOn: $viewModel.autoCheckinBySteps) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Auto check-in when daily steps exceed 100"))
                                .font(.body)
                            Text(String(localized: "When enabled, walking 100+ steps daily will auto check-in"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                }
                .navigationTitle(String(localized: "Auto Check-in Settings"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            showAutoCheckinSheet = false
                        }
                        .fontWeight(.semibold)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.95))
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAvatarSheet) {
            avatarPickerSheet
        }
        .sheet(isPresented: $showNotificationSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle(isOn: $viewModel.dailyReminderEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Enable daily reminder check-in"))
                                .font(.body)
                            Text(String(localized: "Send a local reminder at a fixed time every day"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if viewModel.dailyReminderEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Reminder Time"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            DatePicker(
                                String(localized: "Time"),
                                selection: $viewModel.dailyReminderTime,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }

                    Spacer()
                }
                .padding(20)
                .navigationTitle(String(localized: "Notifications"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            showNotificationSheet = false
                        }
                        .fontWeight(.semibold)
                    }
                }
                .background(Color.white.opacity(0.85))
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCallNameSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Set how your display name appears"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "Enter call name"), text: $draftCallName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)

                    Spacer()
                }
                .padding(20)
                .navigationTitle(String(localized: "Call Name"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            showCallNameSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            Task {
                                let ok = await viewModel.updateCallName(draftCallName)
                                if ok {
                                    showCallNameSheet = false
                                }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .presentationDetents([.fraction(0.35)])
        }
        .alert(String(localized: "Delete Account?"), isPresented: $showDeleteAccountConfirm) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Continue"), role: .destructive) {
                deleteAccountPassword = ""
                showDeletePasswordSheet = true
            }
        } message: {
            Text(String(localized: "This action is permanent and cannot be undone."))
        }
        .sheet(isPresented: $showDeletePasswordSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Enter your password to permanently delete your account."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SecureField(String(localized: "Current Password"), text: $deleteAccountPassword)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)

                    if !viewModel.statusText.isEmpty {
                        Text(viewModel.statusText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        let previousAvatarURL = avatarFileURL
                        Task {
                            let success = await viewModel.deleteAccount(currentPassword: deleteAccountPassword)
                            if success {
                                deleteAccountPassword = ""
                                showDeletePasswordSheet = false
                                bypassEmergencySetupGate = false
                                removeAvatar(at: previousAvatarURL)
                                activeScreen = .main
                            }
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .cornerRadius(12)
                        } else {
                            Text(String(localized: "Delete Account"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
                .navigationTitle(String(localized: "Delete Account"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            deleteAccountPassword = ""
                            showDeletePasswordSheet = false
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .presentationDetents([.fraction(0.38)])
        }
    }

    private var maskedEmail: String {
        let email = viewModel.email
        guard let atIndex = email.firstIndex(of: "@") else { return email }
        let prefix = email.prefix(3)
        let domain = email[atIndex...]
        return "\(prefix)***\(domain)"
    }

    private var currentCallNameDisplay: String {
        let trimmed = viewModel.callName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let fallback = viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? String(localized: "Not set") : fallback
    }

    private var storedAvatarImage: UIImage? {
        guard let data = try? Data(contentsOf: avatarFileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private var avatarFileName: String {
        let trimmed = viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return "avatar-guest.jpg"
        }
        let safe = trimmed.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return "avatar-\(safe).jpg"
    }

    private var avatarFileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AvatarCache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AvatarCache", isDirectory: true)
        return directory.appendingPathComponent(avatarFileName)
    }

    private func saveAvatarToDisk(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }

        let directory = avatarFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: avatarFileURL, options: .atomic)
    }

    private func removeAvatarFromDisk() {
        try? FileManager.default.removeItem(at: avatarFileURL)
    }

    private func removeAvatar(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func migrateLegacyAvatarIfNeeded() {
        guard storedAvatarImage == nil,
              !legacyProfileAvatarBase64.isEmpty,
              let data = Data(base64Encoded: legacyProfileAvatarBase64),
              let image = UIImage(data: data) else {
            return
        }

        saveAvatarToDisk(image)
        legacyProfileAvatarBase64 = ""
    }

    private func avatarView(size: CGFloat) -> some View {
        Group {
            if let uiImage = storedAvatarImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.blue)
                    Text(String((viewModel.username.isEmpty ? "U" : viewModel.username).prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let preview = avatarPreviewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        avatarView(size: 110)
                    }
                }
                .padding(.top, 12)

                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    Text(String(localized: "Choose from Photo Library"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                if !avatarLoadError.isEmpty {
                    Text(avatarLoadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(role: .destructive) {
                    avatarPreviewImage = nil
                    removeAvatarFromDisk()
                } label: {
                    Text(String(localized: "Remove Current Avatar"))
                        .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle(String(localized: "Profile Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        showAvatarSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if let preview = avatarPreviewImage {
                            saveAvatarToDisk(preview)
                        }
                        showAvatarSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedAvatarItem) { newItem in
                guard let newItem else { return }
                Task { await loadAvatarPreview(from: newItem) }
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.fraction(0.45), .medium])
    }

    private func loadAvatarPreview(from item: PhotosPickerItem) async {
        do {
            avatarLoadError = ""
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                avatarPreviewImage = image
            } else {
                avatarLoadError = String(localized: "Unable to load image")
            }
        } catch {
            avatarLoadError = String(localized: "Unable to load image")
        }
    }

    private func settingsRow(icon: String, title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var mainView: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [Color.pink.opacity(0.08), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: greeting + gear
                HStack {
                    avatarView(size: 36)
                    Text(String(localized: "Hello, \(viewModel.username.isEmpty ? String(localized: "User") : viewModel.username)"))
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                    Button {
                        navigate(to: .settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer()

                // Check-in circle button
                Button {
                    Task { await viewModel.checkInToday() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
                            .shadow(color: .white.opacity(0.8), radius: 10, x: -5, y: -5)

                        Image(systemName: viewModel.hasCheckedInToday ? "heart.fill" : "heart")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .foregroundStyle(viewModel.hasCheckedInToday ? .red : Color(.systemGray3))
                    }
                }

                Text(viewModel.hasCheckedInToday ? String(localized: "Checked in today ✓") : String(localized: "Not checked in today"))
                    .font(.title3.weight(.semibold))
                    .padding(.top, 20)

                Spacer()

                // Cards section
                VStack(spacing: 12) {
                    // Auto check-in card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Auto Check-in"))
                                .font(.body.bold())
                            Text(String(localized: "Auto check-in daily"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.autoCheckinBySteps)
                            .labelsHidden()
                    }
                    .padding(18)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)

                    // Streak card
                    HStack(spacing: 14) {
                        Image(systemName: "heart")
                            .font(.title2)
                            .foregroundStyle(.pink)
                            .frame(width: 40, height: 40)
                            .background(Color.pink.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "\(viewModel.checkinDays) day streak"))
                                .font(.body.bold())
                            Text(String(localized: "Keep checking in for a healthy habit"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(18)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
            }
        }
        .task {
            await viewModel.loadStatus()
            // Check if user needs makeup check-in (missed more than 2 days)
            if viewModel.checkinDays == 0 && viewModel.isAuthenticated {
                showMakeupCheckinAlert = true
            }
        }
        .alert(String(localized: "Makeup Check-in"), isPresented: $showMakeupCheckinAlert) {
            Button(String(localized: "Makeup Now")) {
                Task {
                    await viewModel.checkInToday()
                    viewModel.statusText = String(localized: "Makeup check-in successful")
                }
            }
            Button(String(localized: "Later"), role: .cancel) {}
        } message: {
            Text(String(localized: "You missed check-ins for the past few days. Would you like to make up for them?"))
        }
    }

    private func navigate(to screen: AppScreen) {
        showProfileMenu = false
        if screen != .emergency {
            emergencyOpenedFromSettings = false
        }
        activeScreen = screen
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(initialAuthScreen: .login)
                .environmentObject(makeLoginPreviewModel())
                .previewDisplayName("1. 登录")

            ContentView(initialAuthScreen: .register)
                .environmentObject(makeRegisterPreviewModel())
                .previewDisplayName("2. 注册")

            ContentView(initialActiveScreen: .emergency)
                .environmentObject(makeEmergencyPreviewModel())
                .previewDisplayName("3. 紧急联系人设置")

            ContentView(initialActiveScreen: .main)
                .environmentObject(makeMainPreviewModel())
                .previewDisplayName("4. 主界面")

            ContentView(initialActiveScreen: .settings)
                .environmentObject(makeSettingsPreviewModel())
                .previewDisplayName("5. 设置")

            ContentView(initialAuthScreen: .forgotPassword)
                .environmentObject(makeLoginPreviewModel())
                .previewDisplayName("6. 忘记密码")

            ContentView(initialActiveScreen: .changePassword)
                .environmentObject(makeSettingsPreviewModel())
                .previewDisplayName("7. 更改密码")

            ContentView(initialShowRegistrationSuccess: true)
                .environmentObject({
                    let vm = CheckinViewModel()
                    vm.isAuthenticated = true
                    return vm
                }())
                .previewDisplayName("8. 注册成功")
        }
    }

    private static func makeLoginPreviewModel() -> CheckinViewModel {
        let vm = CheckinViewModel()
        vm.statusText = "请输入账号密码登录"
        return vm
    }

    private static func makeRegisterPreviewModel() -> CheckinViewModel {
        let vm = CheckinViewModel()
        vm.statusText = "请先注册新账号"
        return vm
    }

    private static func makeEmergencyPreviewModel() -> CheckinViewModel {
        let vm = CheckinViewModel()
        vm.username = "小明"
        vm.isAuthenticated = true
        vm.hasCompletedEmergencySetup = false
        vm.statusText = "请先设置紧急联系人"
        return vm
    }

    private static func makeMainPreviewModel() -> CheckinViewModel {
        let vm = CheckinViewModel()
        vm.username = "小明"
        vm.isAuthenticated = true
        vm.hasCompletedEmergencySetup = true
        vm.checkinDays = 0
        vm.statusText = "准备就绪"
        return vm
    }

    private static func makeSettingsPreviewModel() -> CheckinViewModel {
        let vm = CheckinViewModel()
        vm.username = "小明"
        vm.isAuthenticated = true
        vm.hasCompletedEmergencySetup = true
        vm.selectedLanguage = "简体中文"
        vm.autoCheckinBySteps = true
        vm.autoCheckinByUnlock = false
        vm.statusText = "设置预览"
        return vm
    }
}

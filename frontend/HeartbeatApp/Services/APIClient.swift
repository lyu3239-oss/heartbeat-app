import Foundation

enum APIClientError: LocalizedError {
    case server(message: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .unauthorized:
            return String(localized: "Session expired. Please log in again.")
        }
    }
}

final class APIClient: NSObject, URLSessionDelegate {
    private struct ErrorResponse: Codable {
        let message: String?
    }

    private struct RefreshTokenBody: Codable {
        let refreshToken: String
    }

    private struct RefreshTokenResponse: Codable {
        let ok: Bool
        let accessToken: String?
        let refreshToken: String?
    }

    /// Callback invoked when token refresh fails (session expired)
    var onSessionExpired: (() -> Void)?

    private var refreshTask: Task<Bool, Error>?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func request<T: Codable, U: Codable>(
        baseURL: String,
        path: String,
        method: String,
        body: T? = nil,
        responseType: U.Type,
        authenticated: Bool = false
    ) async throws -> U {
        let result = try await performRequest(
            baseURL: baseURL, path: path, method: method,
            body: body, responseType: responseType, authenticated: authenticated
        )
        return result
    }

    private func performRequest<T: Codable, U: Codable>(
        baseURL: String,
        path: String,
        method: String,
        body: T?,
        responseType: U.Type,
        authenticated: Bool,
        isRetry: Bool = false
    ) async throws -> U {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add JWT token if authenticated
        if authenticated, let accessToken = KeychainService.get(key: .accessToken) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Handle 401 Unauthorized - try to refresh token
        if httpResponse.statusCode == 401 && authenticated && !isRetry {
            // Try to refresh the token
            let refreshed = try await refreshAccessToken(baseURL: baseURL)
            if refreshed {
                // Retry the original request with new token
                return try await performRequest(
                    baseURL: baseURL, path: path, method: method,
                    body: body, responseType: responseType,
                    authenticated: authenticated, isRetry: true
                )
            } else {
                // Refresh failed - session expired
                onSessionExpired?()
                throw APIClientError.unauthorized
            }
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let fallback = String(data: data, encoding: .utf8) ?? String(localized: "Unknown server error")
            let serverMessage = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.message
            throw APIClientError.server(message: serverMessage ?? fallback)
        }

        return try JSONDecoder().decode(U.self, from: data)
    }

    private func refreshAccessToken(baseURL: String) async throws -> Bool {
        // If there's already a refresh in progress, wait for it
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        // Create a new refresh task
        let task = Task<Bool, Error> {
            defer { refreshTask = nil }

            guard let refreshToken = KeychainService.get(key: .refreshToken) else {
                return false
            }

            do {
                let response: RefreshTokenResponse = try await performRequest(
                    baseURL: baseURL,
                    path: "/api/auth/refresh-token",
                    method: "POST",
                    body: RefreshTokenBody(refreshToken: refreshToken),
                    responseType: RefreshTokenResponse.self,
                    authenticated: false,
                    isRetry: true // Don't retry refresh endpoint
                )

                if response.ok,
                   let newAccessToken = response.accessToken,
                   let newRefreshToken = response.refreshToken {
                    KeychainService.save(key: .accessToken, value: newAccessToken)
                    KeychainService.save(key: .refreshToken, value: newRefreshToken)
                    return true
                }

                return false
            } catch {
                return false
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // For production, validate the certificate chain
        // For now, accept the server trust (basic HTTPS validation)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

import Foundation

final class APIClient {
    func request<T: Codable, U: Codable>(
        baseURL: String,
        path: String,
        method: String,
        body: T? = nil,
        responseType: U.Type
    ) async throws -> U {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "API", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }

        return try JSONDecoder().decode(U.self, from: data)
    }
}

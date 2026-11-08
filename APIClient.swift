import Foundation
import Security

// Ustaw API_BASE_URL w Info.plist, np. https://api.twojadomena.pl
// Ścieżki API są automatycznie uzupełniane prefiksem /api.
final class APIClient {
    static let shared = APIClient()
    private init() {}

private var baseURL: String {
    let value = Bundle.main.object(
        forInfoDictionaryKey: "API_BASE_URL"
    ) as? String

    return (value ?? "http://192.168.1.173:5000")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

    func request(
        _ method: String = "GET",
        _ path: String,
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> [String: Any] {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/api/\(cleanPath)") else {
            throw APIError.message("Nieprawidłowy URL backendu. Sprawdź API_BASE_URL w Info.plist.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = KeychainToken.read(), authenticated {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.message("Nieprawidłowa odpowiedź serwera.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let message = json["message"] as? String ?? "Błąd HTTP \(http.statusCode)."
            throw APIError.http(status: http.statusCode, message: message)
        }
        guard !json.isEmpty else { throw APIError.message("Serwer zwrócił nieprawidłową odpowiedź JSON.") }
        return json
    }
}

enum APIError: LocalizedError {
    case message(String)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .http(_, let message): return message
        }
    }

    var statusCode: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}

enum KeychainToken {
    private static let account = "naspacerze.jwt"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "pl.naspacerze.ios",
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "pl.naspacerze.ios",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "pl.naspacerze.ios",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Dictionary where Key == String, Value == Any {
    func text(_ key: String, fallback: String = "") -> String {
        guard let value = self[key], !(value is NSNull) else { return fallback }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return fallback
    }

    func number(_ key: String, fallback: Double = 0) -> Double {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let string = self[key] as? String, let value = Double(string) { return value }
        return fallback
    }

    func flag(_ key: String) -> Bool {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        if let value = self[key] as? String { return value == "1" || value.lowercased() == "true" }
        return false
    }

    func objects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}

import Foundation
import SwiftUI

struct AppUser: Identifiable, Equatable {
    let id: String
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var address: String
    var role: String

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
    var isStaff: Bool { role == "admin" || role == "caretaker" }

    init(json: [String: Any]) {
        id = json.text("id")
        firstName = json.text("first_name")
        lastName = json.text("last_name")
        email = json.text("email")
        phone = json.text("phone")
        address = json.text("address")
        role = json.text("role", fallback: "client")
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published var isLoading = true
    @Published var errorMessage: String?

    func restore() async {
        defer { isLoading = false }
        guard KeychainToken.read() != nil else { return }
        do {
            let response = try await APIClient.shared.request("GET", "auth/me")
            if let userJSON = response["user"] as? [String: Any] {
                user = AppUser(json: userJSON)
            } else {
                logout()
            }
        } catch {
            logout()
            errorMessage = error.localizedDescription
        }
    }

    func login(email: String, password: String) async throws {
        let response = try await APIClient.shared.request(
            "POST", "auth/login",
            body: ["email": email, "password": password],
            authenticated: false
        )
        guard let token = response["token"] as? String,
              let userJSON = response["user"] as? [String: Any] else {
            throw APIError.message("Serwer nie zwrócił tokenu lub danych użytkownika.")
        }
        KeychainToken.save(token)
        user = AppUser(json: userJSON)
        errorMessage = nil
    }

    func register(firstName: String, lastName: String, email: String, phone: String, address: String, password: String) async throws {
        let response = try await APIClient.shared.request(
            "POST", "auth/register",
            body: [
                "first_name": firstName,
                "last_name": lastName,
                "email": email,
                "phone": phone,
                "address": address,
                "password": password,
                "password_confirm": password
            ],
            authenticated: false
        )
        guard let token = response["token"] as? String,
              let userJSON = response["user"] as? [String: Any] else {
            throw APIError.message("Serwer nie zwrócił tokenu lub danych użytkownika.")
        }
        KeychainToken.save(token)
        user = AppUser(json: userJSON)
        errorMessage = nil
    }

    func logout() {
        KeychainToken.delete()
        user = nil
    }
}

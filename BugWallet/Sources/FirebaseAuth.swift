import Foundation

/// A signed-in Bug Coffee account.
/// `uid` is the Firebase Auth UID — this exact string is what the QR encodes
/// and what shop staff scan.
struct Account: Equatable, Sendable {
    let uid: String
    let email: String
    let idToken: String
    let refreshToken: String
}

enum AuthError: LocalizedError {
    case network(Error)
    case badResponse
    case firebase(String)

    var errorDescription: String? {
        switch self {
        case .network(let e): return e.localizedDescription
        case .badResponse:    return "Unexpected response from the server."
        case .firebase(let code):
            // Map the common Identity Toolkit error codes to friendly text.
            switch code {
            case "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
                return "Wrong email or password."
            case "USER_DISABLED":
                return "This account has been disabled."
            case "TOO_MANY_ATTEMPTS_TRY_LATER":
                return "Too many attempts. Please try again later."
            default:
                return code
            }
        }
    }
}

/// Talks directly to Google Identity Toolkit, exactly like the web app's
/// `signInWithEmailAndPassword`. Auth is NOT App Check-gated, so this works
/// from a native app with only the public API key.
enum FirebaseAuth {
    /// Public Firebase Web config, safe to embed.
    static let apiKey = "AIzaSyDjY4FROGGt9h4Q-V_3InC8Nv2sEeA-FxI"

    static func signIn(email: String, password: String,
                       session: URLSession = .shared) async throws -> Account {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AuthError.network(error)
        }

        guard let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "UNKNOWN_ERROR"
            // Identity Toolkit sometimes appends details after a space, e.g. "INVALID_PASSWORD : ...".
            throw AuthError.firebase(message.components(separatedBy: " ").first ?? message)
        }

        guard let uid = json["localId"] as? String,
              let idToken = json["idToken"] as? String else {
            throw AuthError.badResponse
        }

        return Account(
            uid: uid,
            email: (json["email"] as? String) ?? email,
            idToken: idToken,
            refreshToken: (json["refreshToken"] as? String) ?? ""
        )
    }
}

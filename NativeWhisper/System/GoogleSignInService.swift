import AppKit
import AuthenticationServices
import Foundation

struct GoogleOAuthTokens: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval?
}

enum GoogleSignInError: LocalizedError, Equatable {
    case callbackURLMissing
    case callbackSchemeMissing
    case browserSessionFailedToStart
    case cancelled
    case missingAccessToken
    case missingRefreshToken
    case oauthError(message: String)

    var errorDescription: String? {
        switch self {
        case .callbackURLMissing:
            return "Sign-in did not return a callback URL."
        case .callbackSchemeMissing:
            return "Google sign-in callback URL scheme is missing."
        case .browserSessionFailedToStart:
            return "Failed to start Google sign-in browser session."
        case .cancelled:
            return "Sign-in was cancelled."
        case .missingAccessToken:
            return "Google sign-in did not return an access token."
        case .missingRefreshToken:
            return "Google sign-in did not return a refresh token."
        case .oauthError(let message):
            return message
        }
    }
}

@MainActor
protocol GoogleSignInProviding {
    func authenticate(startURL: URL) async throws -> GoogleOAuthTokens
}

@MainActor
final class GoogleSignInService: NSObject, GoogleSignInProviding, ASWebAuthenticationPresentationContextProviding {
    private let callbackScheme: String
    private var webSession: ASWebAuthenticationSession?

    init(callbackURL: URL) {
        self.callbackScheme = callbackURL.scheme ?? ""
    }

    func authenticate(startURL: URL) async throws -> GoogleOAuthTokens {
        guard !callbackScheme.isEmpty else {
            throw GoogleSignInError.callbackSchemeMissing
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webSession = nil

                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.callbackURLMissing)
                    return
                }

                do {
                    let tokens = try Self.extractTokens(from: callbackURL)
                    continuation.resume(returning: tokens)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session

            guard session.start() else {
                webSession = nil
                continuation.resume(throwing: GoogleSignInError.browserSessionFailedToStart)
                return
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let keyWindow = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = NSApplication.shared.windows.first {
            return firstWindow
        }
        return ASPresentationAnchor()
    }

    private static func extractTokens(from callbackURL: URL) throws -> GoogleOAuthTokens {
        let parameters = callbackParameters(from: callbackURL)

        if let oauthError = parameters["error"], !oauthError.isEmpty {
            let description = parameters["error_description"] ?? oauthError
            throw GoogleSignInError.oauthError(message: description.replacingOccurrences(of: "+", with: " "))
        }

        guard let accessToken = parameters["access_token"], !accessToken.isEmpty else {
            throw GoogleSignInError.missingAccessToken
        }

        guard let refreshToken = parameters["refresh_token"], !refreshToken.isEmpty else {
            throw GoogleSignInError.missingRefreshToken
        }

        let expiresIn = parameters["expires_in"].flatMap { TimeInterval($0) }
        return GoogleOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn
        )
    }

    private static func callbackParameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                parameters[item.name] = item.value ?? ""
            }
        }

        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
           let fragmentComponents = URLComponents(string: "?\(fragment)"),
           let fragmentItems = fragmentComponents.queryItems {
            for item in fragmentItems {
                parameters[item.name] = item.value ?? ""
            }
        }

        return parameters
    }
}

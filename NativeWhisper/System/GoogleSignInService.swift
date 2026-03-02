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

private func googleAuthCallbackParameters(from url: URL) -> [String: String] {
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

private func extractGoogleOAuthTokens(from callbackURL: URL) throws -> GoogleOAuthTokens {
    let parameters = googleAuthCallbackParameters(from: callbackURL)

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

@MainActor
protocol GoogleSignInProviding {
    func authenticate(startURL: URL) async throws -> GoogleOAuthTokens
}

private final class GoogleSignInCallbackRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private let complete: @Sendable (Result<GoogleOAuthTokens, Error>) -> Void

    init(complete: @escaping @Sendable (Result<GoogleOAuthTokens, Error>) -> Void) {
        self.complete = complete
    }

    func handle(callbackURL: URL?, error: Error?) {
        let result: Result<GoogleOAuthTokens, Error>

        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            result = .failure(GoogleSignInError.cancelled)
        } else if let error {
            result = .failure(error)
        } else if let callbackURL {
            do {
                result = .success(try extractGoogleOAuthTokens(from: callbackURL))
            } catch {
                result = .failure(error)
            }
        } else {
            result = .failure(GoogleSignInError.callbackURLMissing)
        }

        finishOnce(with: result)
    }

    func failStart() {
        finishOnce(with: .failure(GoogleSignInError.browserSessionFailedToStart))
    }

    private func finishOnce(with result: Result<GoogleOAuthTokens, Error>) {
        lock.lock()
        let shouldComplete = !isFinished
        if shouldComplete {
            isFinished = true
        }
        lock.unlock()

        guard shouldComplete else {
            return
        }

        complete(result)
    }
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
            let relay = GoogleSignInCallbackRelay { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.webSession = nil
                    continuation.resume(with: result)
                }
            }

            let callbackHandler: @Sendable (URL?, Error?) -> Void = { callbackURL, error in
                relay.handle(callbackURL: callbackURL, error: error)
            }

            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: callbackScheme,
                completionHandler: callbackHandler
            )

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session

            guard session.start() else {
                webSession = nil
                relay.failStart()
                return
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return Self.currentPresentationAnchor()
        }

        var anchor = ASPresentationAnchor()
        DispatchQueue.main.sync {
            anchor = Self.currentPresentationAnchor()
        }
        return anchor
    }

    private static func currentPresentationAnchor() -> ASPresentationAnchor {
        if let keyWindow = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = NSApplication.shared.windows.first {
            return firstWindow
        }
        return ASPresentationAnchor()
    }

}

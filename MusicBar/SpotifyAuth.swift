//
//  SpotifyAuth.swift
//  MusicBar
//

import AuthenticationServices
import Combine
import CryptoKit
import Security

@MainActor
final class SpotifyAuth: NSObject, ObservableObject {

    static let shared = SpotifyAuth()

    // MARK: - Config

    private let clientID    = "53730145f4924c078959a4edebf5b201"
    private let redirectURI = "musicbar://spotify-callback"
    private let scopes      = "user-modify-playback-state"

    // MARK: - State

    @Published var isAuthorized = false

    private var codeVerifier = ""
    private var authSession: ASWebAuthenticationSession?
    private var anchorWindow: NSWindow?

    override init() {
        super.init()
        isAuthorized = Keychain.read("spotify_refresh_token") != nil
    }

    var accessToken: String? { Keychain.read("spotify_access_token") }

    // MARK: - Start OAuth (PKCE)

    func startAuth() {
        anchorWindow = NSApp.keyWindow
        codeVerifier = Self.makeVerifier()
        let challenge = Self.makeChallenge(codeVerifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id",            value: clientID),
            .init(name: "response_type",         value: "code"),
            .init(name: "redirect_uri",          value: redirectURI),
            .init(name: "scope",                 value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge",        value: challenge),
        ]

        authSession = ASWebAuthenticationSession(
            url: comps.url!,
            callbackURLScheme: "musicbar"
        ) { [weak self] callbackURL, error in
            guard let self, let url = callbackURL, error == nil,
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            Task { await self.exchange(code: code) }
        }
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    // MARK: - Code → tokens

    private func exchange(code: String) async {
        let req = tokenRequest([
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientID,
            "code_verifier": codeVerifier,
        ])
        guard let tokens = try? await fetch(req) else { return }
        save(tokens)
    }

    // MARK: - Refresh (called by SpotifyAPI on 401)

    func refresh() async throws {
        guard let stored = Keychain.read("spotify_refresh_token") else {
            isAuthorized = false
            throw SpotifyAuthError.notAuthorized
        }
        let req = tokenRequest([
            "grant_type":    "refresh_token",
            "refresh_token": stored,
            "client_id":     clientID,
        ])
        let tokens = try await fetch(req)
        save(tokens)
    }

    // MARK: - Helpers

    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String?
    }

    private func tokenRequest(_ body: [String: String]) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return req
    }

    private func fetch(_ req: URLRequest) async throws -> Tokens {
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(Tokens.self, from: data)
    }

    private func save(_ t: Tokens) {
        Keychain.write("spotify_access_token", t.access_token)
        if let r = t.refresh_token { Keychain.write("spotify_refresh_token", r) }
        isAuthorized = true
    }

    // MARK: - PKCE

    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 96)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func makeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
    }
}

enum SpotifyAuthError: Error { case notAuthorized }

// MARK: - Keychain

private enum Keychain {
    private static let service = "com.musicbar.spotify"

    static func read(_ key: String) -> String? {
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data,
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }
}

//
//  SpotifyAPI.swift
//  MusicBar
//

import Foundation

enum SpotifyAPI {

    static func playPause(isPlaying: Bool) async {
        // Spotify has separate endpoints for play and pause
        await request(isPlaying ? "me/player/pause" : "me/player/play", method: "PUT")
    }

    static func nextTrack() async {
        await request("me/player/next", method: "POST")
    }

    static func previousTrack() async {
        await request("me/player/previous", method: "POST")
    }

    // MARK: - Core request (auto-refreshes on 401)

    private static func request(_ path: String, method: String, isRetry: Bool = false) async {
        guard let token = SpotifyAuth.shared.accessToken else { return }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 401, !isRetry {
                try await SpotifyAuth.shared.refresh()
                await request(path, method: method, isRetry: true)
            }
        } catch {
            print("[SpotifyAPI] \(method) /\(path) error: \(error)")
        }
    }
}

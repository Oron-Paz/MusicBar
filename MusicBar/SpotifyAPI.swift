//
//  SpotifyAPI.swift
//  MusicBar
//

import Foundation

enum SpotifyAPI {

    struct CurrentPlayback {
        let trackName: String
        let artistName: String
        let albumName: String
        let isPlaying: Bool
        let positionMs: Double
        let durationMs: Double
    }

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

    // MARK: - Current playback state

    static func fetchCurrentPlayback(isRetry: Bool = false) async -> CurrentPlayback? {
        guard let token = SpotifyAuth.shared.accessToken else { return nil }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 401, !isRetry {
                try await SpotifyAuth.shared.refresh()
                return await fetchCurrentPlayback(isRetry: true)
            }

            // 204 = no active device
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any] else { return nil }

            let trackName  = item["name"] as? String ?? ""
            let durationMs = item["duration_ms"] as? Double ?? 0
            let artists    = item["artists"] as? [[String: Any]] ?? []
            let artistName = artists.first?["name"] as? String ?? ""
            let album      = item["album"] as? [String: Any]
            let albumName  = album?["name"] as? String ?? ""
            let isPlaying  = json["is_playing"] as? Bool ?? false
            let positionMs = json["progress_ms"] as? Double ?? 0

            return CurrentPlayback(
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                isPlaying: isPlaying,
                positionMs: positionMs,
                durationMs: durationMs
            )
        } catch {
            print("[SpotifyAPI] GET /me/player error: \(error)")
            return nil
        }
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

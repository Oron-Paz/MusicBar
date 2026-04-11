//
//  PlayerManager.swift
//  MusicBar
//

import AppKit
import Combine

enum PlayerApp {
    case spotify, appleMusic, none
}

struct PlayerState {
    var trackName: String = ""
    var artistName: String = ""
    var albumName: String = ""
    var isPlaying: Bool = false
    var position: Double = 0    // seconds
    var duration: Double = 0    // seconds
    var artwork: NSImage? = nil
    var player: PlayerApp = .none
}

@MainActor
class PlayerManager: ObservableObject {

    @Published var state = PlayerState()

    // Convenience passthroughs for AppDelegate marquee
    var trackName: String { state.trackName }
    var artistName: String { state.artistName }
    var isPlaying: Bool { state.isPlaying }

    // NSAppleScript must NOT run on MainActor — use explicit DispatchQueue
    private let scriptQueue = DispatchQueue(label: "com.musicbar.applescript", qos: .userInitiated)

    // Cache to avoid redundant Spotify artwork fetches
    private var lastArtworkURL: String = ""
    private var lastTrackName: String = ""

    // MARK: - Poll entry point (called from AppDelegate timer)

    func poll() {
        let detected = detectActivePlayer()
        switch detected {
        case .spotify:
            pollSpotify()
        case .appleMusic:
            pollAppleMusic()
        case .none:
            if state.player != .none {
                state = PlayerState()
            }
        }
    }

    // MARK: - Player detection (no AppleScript needed)

    private func detectActivePlayer() -> PlayerApp {
        let running = NSWorkspace.shared.runningApplications
        let spotifyRunning = running.contains { $0.bundleIdentifier == "com.spotify.client" }
        let musicRunning = running.contains { $0.bundleIdentifier == "com.apple.Music" }

        if spotifyRunning && musicRunning {
            // Both running — prefer whichever is currently playing
            // Fall back to Spotify if indeterminate
            return .spotify
        }
        if spotifyRunning { return .spotify }
        if musicRunning { return .appleMusic }
        return .none
    }

    // MARK: - Spotify

    private func pollSpotify() {
        let script = """
        tell application "Spotify"
            if player state is playing or player state is paused then
                set stateStr to "playing"
                if player state is paused then set stateStr to "paused"
                return (name of current track) & "|" & (artist of current track) & "|" & (album of current track) & "|" & (artwork url of current track) & "|" & (player position as string) & "|" & ((duration of current track) as string) & "|" & stateStr
            else
                return "|||0|0|stopped"
            end if
        end tell
        """
        runScript(script) { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.parseSpotifyResult(result)
            }
        }
    }

    private func parseSpotifyResult(_ raw: String) {
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 7 else { return }

        let artURL = parts[3]
        let needsArtwork = artURL != lastArtworkURL && !artURL.isEmpty

        state = PlayerState(
            trackName: parts[0],
            artistName: parts[1],
            albumName: parts[2],
            isPlaying: parts[6] == "playing",
            position: Double(parts[4]) ?? 0,
            duration: (Double(parts[5]) ?? 0) / 1000.0,  // Spotify returns milliseconds
            artwork: needsArtwork ? nil : state.artwork,
            player: .spotify
        )

        if needsArtwork {
            lastArtworkURL = artURL
            fetchSpotifyArtwork(urlString: artURL)
        }
    }

    private func fetchSpotifyArtwork(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.state.artwork = image
            }
        }.resume()
    }

    // MARK: - Apple Music

    private func pollAppleMusic() {
        let script = """
        tell application "Music"
            if player state is playing or player state is paused then
                set stateStr to "playing"
                if player state is paused then set stateStr to "paused"
                return (name of current track) & "|" & (artist of current track) & "|" & (album of current track) & "|" & (player position as string) & "|" & (duration of current track as string) & "|" & stateStr
            else
                return "|||0|0|stopped"
            end if
        end tell
        """
        runScript(script) { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.parseAppleMusicResult(result)
            }
        }
    }

    private func parseAppleMusicResult(_ raw: String) {
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 6 else { return }

        let trackChanged = parts[0] != lastTrackName
        if trackChanged { lastTrackName = parts[0] }

        state = PlayerState(
            trackName: parts[0],
            artistName: parts[1],
            albumName: parts[2],
            isPlaying: parts[5] == "playing",
            position: Double(parts[3]) ?? 0,
            duration: Double(parts[4]) ?? 0,  // Apple Music returns seconds
            artwork: trackChanged ? nil : state.artwork,
            player: .appleMusic
        )

        if trackChanged {
            fetchAppleMusicArtwork()
        }
    }

    private func fetchAppleMusicArtwork() {
        // Artwork returns binary data — cannot be concatenated into the pipe-delimited string.
        // Must be a separate AppleScript call that returns raw data via the descriptor.
        let script = """
        tell application "Music"
            if player state is playing or player state is paused then
                try
                    return raw data of artwork 1 of current track
                on error
                    return ""
                end try
            end if
        end tell
        """
        scriptQueue.async { [weak self] in
            guard let self else { return }
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let descriptor = appleScript?.executeAndReturnError(&error)
            guard let data = descriptor?.data, !data.isEmpty,
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.state.artwork = image
            }
        }
    }

    // MARK: - Generic script runner

    /// Executes an AppleScript on the background queue and returns the string result on main.
    private func runScript(_ source: String, completion: @escaping @MainActor (String?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let descriptor = script?.executeAndReturnError(&error)
            let result = descriptor?.stringValue
            if let error {
                print("[PlayerManager] AppleScript error: \(error)")
            }
            Task { @MainActor in
                completion(result)
            }
        }
    }

    // MARK: - Transport commands

    func playPause() {
        transport(spotify: "tell application \"Spotify\" to playpause",
                  music:   "tell application \"Music\" to playpause")
    }

    func previousTrack() {
        transport(spotify: "tell application \"Spotify\" to previous track",
                  music:   "tell application \"Music\" to previous track")
    }

    func nextTrack() {
        transport(spotify: "tell application \"Spotify\" to next track",
                  music:   "tell application \"Music\" to next track")
    }

    private func transport(spotify: String, music: String) {
        switch state.player {
        case .spotify:    runScript(spotify, completion: { _ in })
        case .appleMusic: runScript(music,   completion: { _ in })
        case .none:       break
        }
    }
}

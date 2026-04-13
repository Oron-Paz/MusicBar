//
//  PlayerManager.swift
//  MusicBar
//

import AppKit
import Combine

enum PlayerApp: Equatable {
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
    @Published var highlightedControl: String? = nil   // "playPause" | "next" | "previous"

    private var playbackStartedAt: Date?
    private var positionAtStart: Double = 0
    private let scriptQueue = DispatchQueue(label: "com.musicbar.applescript", qos: .userInitiated)

    // MARK: - Setup

    func startObserving() {
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(self, selector: #selector(spotifyChanged(_:)),
                       name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        nc.addObserver(self, selector: #selector(appleMusicChanged(_:)),
                       name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
    }

    // MARK: - Spotify notification handler

    @objc private func spotifyChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]

        let statusRaw = info["Player State"] as? String ?? ""
        let isPlaying = statusRaw == "Playing"
        let isPaused  = statusRaw == "Paused"

        guard isPlaying || isPaused else {
            state = PlayerState()
            return
        }

        let name     = info["Name"]              as? String ?? ""
        let artist   = info["Artist"]            as? String ?? ""
        let album    = info["Album"]             as? String ?? ""
        let duration = (info["Duration"]         as? Double ?? 0) / 1000.0
        let position = info["Playback Position"] as? Double ?? 0

        // Compute trackChanged before updating state
        let trackChanged = name != state.trackName

        state = PlayerState(
            trackName: name,
            artistName: artist,
            albumName: album,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            artwork: trackChanged ? nil : state.artwork,
            player: .spotify
        )

        if trackChanged || state.artwork == nil {
            fetchSpotifyArtwork(track: name, artist: artist)
        }

        if isPlaying {
            playbackStartedAt = Date()
            positionAtStart = position
        } else {
            playbackStartedAt = nil
        }
    }

    // MARK: - Spotify artwork via iTunes Search API

    private var lastArtworkTrack = ""

    private func fetchSpotifyArtwork(track: String, artist: String) {
        let query = "\(track) \(artist)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              query != lastArtworkTrack else { return }
        lastArtworkTrack = query

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term",   value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit",  value: "1"),
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first   = results.first,
                  let artStr  = first["artworkUrl100"] as? String else { return }

            let highRes = artStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard let artURL = URL(string: highRes) else { return }

            URLSession.shared.dataTask(with: artURL) { [weak self] imgData, _, _ in
                guard let self, let imgData, let image = NSImage(data: imgData) else { return }
                Task { @MainActor [weak self] in self?.state.artwork = image }
            }.resume()
        }.resume()
    }

    // MARK: - Apple Music notification handler

    @objc private func appleMusicChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]

        let statusRaw = info["Player State"] as? String ?? ""
        let isPlaying = statusRaw == "Playing"
        let isPaused  = statusRaw == "Paused"

        guard isPlaying || isPaused else {
            state = PlayerState()
            return
        }

        let name     = info["Name"]       as? String ?? ""
        let artist   = info["Artist"]     as? String ?? ""
        let album    = info["Album"]      as? String ?? ""
        let duration = info["Total Time"] as? Double ?? 0
        let position = info["Start Time"] as? Double ?? 0

        let trackChanged = name != state.trackName

        state = PlayerState(
            trackName: name,
            artistName: artist,
            albumName: album,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            artwork: trackChanged ? nil : state.artwork,
            player: .appleMusic
        )

        if isPlaying {
            playbackStartedAt = Date()
            positionAtStart = position
        } else {
            playbackStartedAt = nil
        }

        if trackChanged { fetchAppleMusicArtwork() }
    }

    // MARK: - Apple Music artwork via AppleScript

    private func fetchAppleMusicArtwork() {
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
            let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)
            guard let data = descriptor?.data, !data.isEmpty,
                  let image = NSImage(data: data) else { return }
            Task { @MainActor [weak self] in self?.state.artwork = image }
        }
    }

    // MARK: - Apple Music transport via AppleScript

    private func appleMusicCommand(_ command: String) {
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Music\" to \(command)")?.executeAndReturnError(&error)
        }
    }

    // MARK: - Spotify state refresh (call on launch / popover open)

    func refreshFromSpotify() {
        guard SpotifyAuth.shared.isAuthorized else { return }
        Task {
            guard let playback = await SpotifyAPI.fetchCurrentPlayback() else { return }
            let trackChanged = playback.trackName != state.trackName
            state = PlayerState(
                trackName: playback.trackName,
                artistName: playback.artistName,
                albumName: playback.albumName,
                isPlaying: playback.isPlaying,
                position: playback.positionMs / 1000.0,
                duration: playback.durationMs / 1000.0,
                artwork: trackChanged ? nil : state.artwork,
                player: .spotify
            )
            if playback.isPlaying {
                playbackStartedAt = Date()
                positionAtStart = playback.positionMs / 1000.0
            } else {
                playbackStartedAt = nil
            }
            if trackChanged || state.artwork == nil {
                fetchSpotifyArtwork(track: playback.trackName, artist: playback.artistName)
            }
        }
    }

    // MARK: - Position tick

    func poll() { tickPosition() }

    private func tickPosition() {
        guard state.isPlaying, let startedAt = playbackStartedAt else { return }
        state.position = min(positionAtStart + Date().timeIntervalSince(startedAt), state.duration)
    }

    // MARK: - Flash highlight

    private func flash(_ control: String) {
        highlightedControl = control
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            highlightedControl = nil
        }
    }

    // MARK: - Transport commands

    func playPause() {
        flash("playPause")
        switch state.player {
        case .spotify:
            let playing = state.isPlaying
            // Optimistic update — flip immediately, Spotify notification confirms shortly after
            state.isPlaying = !playing
            playbackStartedAt = playing ? nil : Date()
            if !playing { positionAtStart = state.position }
            Task { await SpotifyAPI.playPause(isPlaying: playing) }
        case .appleMusic:
            let playing = state.isPlaying
            state.isPlaying = !playing
            playbackStartedAt = playing ? nil : Date()
            if !playing { positionAtStart = state.position }
            appleMusicCommand("playpause")
        case .none:
            break
        }
    }

    func nextTrack() {
        flash("next")
        switch state.player {
        case .spotify:    Task { await SpotifyAPI.nextTrack() }
        case .appleMusic: appleMusicCommand("next track")
        case .none:       break
        }
    }

    func previousTrack() {
        flash("previous")
        switch state.player {
        case .spotify:    Task { await SpotifyAPI.previousTrack() }
        case .appleMusic: appleMusicCommand("previous track")
        case .none:       break
        }
    }
}

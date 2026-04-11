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

    var trackName: String { state.trackName }
    var artistName: String { state.artistName }
    var isPlaying: Bool { state.isPlaying }

    // Tracks when the last "playing" notification arrived so we can
    // compute elapsed position smoothly between notifications.
    private var playbackStartedAt: Date? = nil
    private var positionAtStart: Double = 0

    // Background queue for artwork-only AppleScript calls
    private let scriptQueue = DispatchQueue(label: "com.musicbar.applescript", qos: .userInitiated)

    // MARK: - Setup

    func startObserving() {
        let nc = DistributedNotificationCenter.default()

        // Spotify broadcasts this every time track or playback state changes
        nc.addObserver(
            self,
            selector: #selector(spotifyChanged(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )

        // Apple Music broadcasts this on track/state changes
        nc.addObserver(
            self,
            selector: #selector(appleMusicChanged(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        print("[PlayerManager] Registered for distributed notifications")
    }

    // MARK: - Spotify notification handler

    @objc private func spotifyChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]
        print("[PlayerManager] Spotify notification: \(info)")

        let statusRaw = info["Player State"] as? String ?? ""
        let isPlaying = statusRaw == "Playing"
        let isPaused  = statusRaw == "Paused"

        guard isPlaying || isPaused else {
            state = PlayerState()
            return
        }

        let name     = info["Name"]             as? String ?? ""
        let artist   = info["Artist"]           as? String ?? ""
        let album    = info["Album"]            as? String ?? ""
        let duration = (info["Duration"]        as? Double ?? 0) / 1000.0  // ms → seconds
        let position = info["Playback Position"] as? Double ?? 0

        state = PlayerState(
            trackName: name,
            artistName: artist,
            albumName: album,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            artwork: state.player == .spotify && state.trackName == name ? state.artwork : nil,
            player: .spotify
        )

        let trackChanged = name != state.trackName
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

    // MARK: - Spotify artwork via iTunes Search API (no auth needed)

    private var lastArtworkTrack = ""

    private func fetchSpotifyArtwork(track: String, artist: String) {
        let query = "\(track) \(artist)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              query != lastArtworkTrack else { return }
        lastArtworkTrack = query

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artURLStr = first["artworkUrl100"] as? String else { return }

            let highRes = artURLStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard let artURL = URL(string: highRes) else { return }

            URLSession.shared.dataTask(with: artURL) { [weak self] imgData, _, _ in
                guard let self, let imgData, let image = NSImage(data: imgData) else { return }
                Task { @MainActor [weak self] in
                    self?.state.artwork = image
                }
            }.resume()
        }.resume()
    }

    // MARK: - Apple Music notification handler

    @objc private func appleMusicChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]
        print("[PlayerManager] Apple Music notification: \(info)")

        let statusRaw = info["Player State"] as? String ?? ""
        let isPlaying = statusRaw == "Playing"
        let isPaused  = statusRaw == "Paused"

        guard isPlaying || isPaused else {
            state = PlayerState()
            return
        }

        let name     = info["Name"]        as? String ?? ""
        let artist   = info["Artist"]      as? String ?? ""
        let album    = info["Album"]       as? String ?? ""
        let duration = info["Total Time"]  as? Double ?? 0
        let position = info["Start Time"]  as? Double ?? 0

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

        if trackChanged {
            fetchAppleMusicArtwork()
        }
    }

    // MARK: - Position tick (called from AppDelegate poll timer)

    func tickPosition() {
        guard state.isPlaying, let startedAt = playbackStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let newPosition = min(positionAtStart + elapsed, state.duration)
        state.position = newPosition
    }

    // MARK: - Apple Music artwork (still uses AppleScript — only for artwork)

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
            let appleScript = NSAppleScript(source: script)
            let descriptor = appleScript?.executeAndReturnError(&error)
            guard let data = descriptor?.data, !data.isEmpty,
                  let image = NSImage(data: data) else { return }
            Task { @MainActor [weak self] in
                self?.state.artwork = image
            }
        }
    }

    // MARK: - Transport commands (media key simulation — no permissions needed)

    func playPause()    { sendMediaKey(16) }  // NX_KEYTYPE_PLAY
    func nextTrack()    { sendMediaKey(17) }  // NX_KEYTYPE_NEXT
    func previousTrack(){ sendMediaKey(18) }  // NX_KEYTYPE_PREVIOUS

    private func sendMediaKey(_ keyCode: Int) {
        func event(down: Bool) -> NSEvent? {
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (keyCode << 16) | ((down ? 0xa : 0xb) << 8),
                data2: -1
            )
        }
        event(down: true)?.cgEvent?.post(tap: .cghidEventTap)
        event(down: false)?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Legacy poll() — kept so AppDelegate timer still compiles

    func poll() {
        tickPosition()
    }
}

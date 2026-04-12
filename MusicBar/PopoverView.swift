//
//  PopoverView.swift
//  MusicBar
//

import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared
    private var state: PlayerState { playerManager.state }

    var body: some View {
        VStack(spacing: 12) {
            artworkView
            trackInfoView
            progressView
            controlsView
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = state.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 190, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 190, height: 190)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    // MARK: - Track info

    @ViewBuilder
    private var trackInfoView: some View {
        VStack(spacing: 4) {
            Text(state.trackName.isEmpty ? "Not Playing" : state.trackName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            if !state.artistName.isEmpty {
                Text(state.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !state.albumName.isEmpty {
                Text(state.albumName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Progress bar

    @ViewBuilder
    private var progressView: some View {
        VStack(spacing: 4) {
            let progress = state.duration > 0 ? min(state.position / state.duration, 1.0) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                Capsule()
                    .fill(Color.primary)
                    .scaleEffect(x: progress, anchor: .leading)
            }
            .frame(height: 4)
            .padding(.horizontal)

            HStack {
                Text(formatTime(state.position))
                Spacer()
                Text(formatTime(state.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsView: some View {
        if state.player == .spotify && !spotifyAuth.isAuthorized {
            Button("Connect Spotify") {
                SpotifyAuth.shared.startAuth()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 14) {
                GlassButton(icon: "backward.fill", size: .medium,
                            isActivated: playerManager.highlightedControl == "previous") {
                    playerManager.previousTrack()
                }
                GlassButton(
                    icon: state.isPlaying ? "pause.fill" : "play.fill",
                    size: .large,
                    isActivated: playerManager.highlightedControl == "playPause"
                ) {
                    playerManager.playPause()
                }
                GlassButton(icon: "forward.fill", size: .medium,
                            isActivated: playerManager.highlightedControl == "next") {
                    playerManager.nextTrack()
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    enum Size {
        case medium, large

        var frame: CGFloat        { self == .large ? 52 : 42 }
        var iconSize: CGFloat     { self == .large ? 19 : 14 }
        var cornerRadius: CGFloat { self == .large ? 16 : 12 }
    }

    let icon: String
    let size: Size
    var isActivated: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size.iconSize, weight: .semibold))
                .frame(width: size.frame, height: size.frame)
                .background {
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .fill(Color.primary.opacity(isActivated ? 0.22 : (isHovered ? 0.12 : 0.07)))
                        .overlay(
                            RoundedRectangle(cornerRadius: size.cornerRadius)
                                .stroke(Color.primary.opacity(isActivated ? 0.5 : 0.15), lineWidth: 0.8)
                        )
                        .shadow(color: Color.white.opacity(isActivated ? 0.45 : 0),
                                radius: isActivated ? 8 : 0)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.spring(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isActivated)
    }
}

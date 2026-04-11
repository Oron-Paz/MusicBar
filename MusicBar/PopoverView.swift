//
//  PopoverView.swift
//  MusicBar
//

import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var playerManager: PlayerManager

    private var state: PlayerState { playerManager.state }

    var body: some View {
        VStack(spacing: 12) {
            artworkView
            trackInfoView
            progressView
            controlsView
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = state.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 200, height: 200)
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
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    let progress = state.duration > 0 ? min(state.position / state.duration, 1.0) : 0
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * progress, height: 4)
                }
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

    // MARK: - Transport controls

    @ViewBuilder
    private var controlsView: some View {
        HStack(spacing: 32) {
            Button { playerManager.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button { playerManager.playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .buttonStyle(.plain)

            Button { playerManager.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

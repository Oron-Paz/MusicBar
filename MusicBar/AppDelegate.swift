//
//  AppDelegate.swift
//  MusicBar
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let playerManager = PlayerManager()

    private var pollTimer: Timer?
    private var marqueeTimer: Timer?

    private var marqueeOffset: Int = 0
    private let marqueeLabel = MenuBarLabel(visibleWidth: 30, padding: "   ")

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        startTimers()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "♪"
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.behavior = .transient  // auto-dismisses on outside click
        popover.animates = true

        let hostingController = NSHostingController(
            rootView: PopoverView(playerManager: playerManager)
        )
        popover.contentViewController = hostingController
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Timers

    private func startTimers() {
        // Data poll every 1.5s
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.playerManager.poll()
        }
        pollTimer?.fire()  // immediate first poll

        // Marquee scroll every 0.3s
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateMarquee()
        }
    }

    // MARK: - Marquee

    private func updateMarquee() {
        guard let button = statusItem.button else { return }

        let track = playerManager.trackName
        let artist = playerManager.artistName

        if track.isEmpty {
            button.title = playerManager.isPlaying ? "♪" : "♩"
            marqueeOffset = 0
            return
        }

        let full = "\(track) — \(artist)"
        let chars = Array(full + marqueeLabel.padding)

        if chars.count <= marqueeLabel.visibleWidth {
            // Short enough — show static, no scrolling
            button.title = full
            marqueeOffset = 0
        } else {
            button.title = marqueeLabel.slice(from: full, offset: marqueeOffset)
            marqueeOffset += 1
        }
    }
}

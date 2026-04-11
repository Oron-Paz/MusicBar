//
//  AppDelegate.swift
//  MusicBar
//

import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let playerManager = PlayerManager()

    private var pollTimer: Timer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        playerManager.startObserving()
        startTimers()
        registerLoginItem()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MusicBar")
            button.image?.isTemplate = true  // adapts to dark/light menu bar automatically
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 340)
        popover.behavior = .transient
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

    // MARK: - Login item

    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
                print("[AppDelegate] Registered as login item")
            }
        } catch {
            print("[AppDelegate] Could not register login item: \(error)")
        }
    }

    // MARK: - Timers

    private func startTimers() {
        // Ticks position forward smoothly every 1s
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.playerManager.poll()
        }
    }
}

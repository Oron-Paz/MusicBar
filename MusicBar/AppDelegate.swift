//
//  AppDelegate.swift
//  MusicBar
//

import AppKit
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let playerManager = PlayerManager()

    private var pollTimer: Timer?
    private var localKeyMonitor: Any?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        playerManager.startObserving()
        startTimers()
        registerLoginItem()
        registerHotkeys()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MusicBar")
            button.image?.isTemplate = true
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
        popover.delegate = self

        let hostingController = NSHostingController(
            rootView: PopoverView(playerManager: playerManager)
        )
        popover.contentViewController = hostingController
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            removeLocalKeyMonitor()
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installLocalKeyMonitor()
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        removeLocalKeyMonitor()
    }

    // MARK: - Local key monitor (active only while popover is open)

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]) else { return event }
            if event.keyCode == UInt16(kVK_ANSI_RightBracket) {
                self?.playerManager.nextTrack()
                return nil
            }
            if event.keyCode == UInt16(kVK_ANSI_LeftBracket) {
                self?.playerManager.previousTrack()
                return nil
            }
            return event
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Login item

    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("[AppDelegate] Could not register login item: \(error)")
        }
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        // ⌘⇧M → open/close popover
        HotkeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.togglePopover()
        }

        // ⌘⇧Space → play/pause
        HotkeyManager.shared.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.playerManager.playPause()
        }
    }

    // MARK: - Timers

    private func startTimers() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.playerManager.poll()
        }
    }
}

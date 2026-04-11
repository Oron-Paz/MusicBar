//
//  MenuBarLabel.swift
//  MusicBar
//

import Foundation

/// Pure value type that computes the visible slice of a scrolling marquee string.
/// Owned and called by AppDelegate on the main queue.
struct MenuBarLabel {

    let visibleWidth: Int
    let padding: String

    init(visibleWidth: Int = 30, padding: String = "   ") {
        self.visibleWidth = visibleWidth
        self.padding = padding
    }

    /// Returns the substring to display given a scroll offset.
    /// The offset is expected to increment by 1 on each call.
    func slice(from full: String, offset: Int) -> String {
        let looping = full + padding
        let chars = Array(looping)
        let len = chars.count

        guard len > visibleWidth else {
            return String(chars.prefix(visibleWidth))
        }

        let start = offset % len
        let end = start + visibleWidth
        if end <= len {
            return String(chars[start..<end])
        } else {
            return String(chars[start...]) + String(chars[0..<(end - len)])
        }
    }
}

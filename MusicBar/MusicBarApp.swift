//
//  MusicBarApp.swift
//  MusicBar
//
//  Created by Oron Paz on 4/11/26.
//

import SwiftUI

@main
struct MusicBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

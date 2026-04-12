# MusicBar

A minimal macOS menu bar app that shows what's playing in Spotify or Apple Music.

- Lives in the menu bar — no Dock icon
- Click the icon to see album art, track info, and playback controls
- Supports Spotify and Apple Music (auto-detects whichever is playing)
- Launches automatically at login

---

## Features

- **Now Playing popover** — album art, track name, artist, album, and a live progress bar
- **Playback controls** — previous, play/pause, and next buttons in the popover
- **Global hotkeys** — control playback from anywhere without opening the popover
- **Auto-detects player** — switches seamlessly between Spotify and Apple Music
- **Login item** — registers itself at first launch, always running when you log in
- **No Dock icon** — stays out of your way, lives only in the menu bar

---

## Hotkeys

| Hotkey | Action |
|---|---|
| `Cmd Shift M` | Open / close the popover |
| `Cmd Shift Space` | Play / pause |
| `Cmd Shift ]` | Next track *(popover must be open)* |
| `Cmd Shift [` | Previous track *(popover must be open)* |

> `Cmd Shift [` and `Cmd Shift ]` only intercept the keys while the popover is open, so they pass through normally to other apps (e.g. browser tab switching) when the popover is closed.

---

## Requirements

- macOS 15 or later
- Xcode 16 or later
- A free Apple Developer account (for code signing)
- Spotify and/or Apple Music
- A Spotify Developer app *(for Spotify playback controls — one-time setup, see below)*

---

## Spotify Setup

MusicBar controls Spotify via the **Spotify Web API**, which requires a one-time OAuth connection.

### 1. Create a Spotify Developer app

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in
2. Click **Create app**
3. Fill in any name and description
4. Under **Redirect URIs**, add exactly: `musicbar://spotify-callback`
5. Save — copy the **Client ID**

### 2. Add your Client ID

Open `MusicBar/SpotifyAuth.swift` and replace the `clientID` value:

```swift
private let clientID = "YOUR_CLIENT_ID_HERE"
```

### 3. Connect from the app

Build and run MusicBar. Play a track in Spotify — the popover will show a **"Connect Spotify"** button. Click it to complete the OAuth flow in your browser. After authorizing, playback controls will work. Tokens are stored in your Keychain and refresh automatically.

---

## Build & Run

1. **Clone the repo**
   ```bash
   git clone https://github.com/YOUR_USERNAME/MusicBar.git
   cd MusicBar
   ```

2. **Open in Xcode**
   ```bash
   open MusicBar.xcodeproj
   ```

3. **Set your Development Team**
   - Click the **MusicBar** project in the sidebar
   - Select the **MusicBar** target → **Signing & Capabilities**
   - Under **Team**, choose your Apple ID (sign in at Xcode → Settings → Accounts if needed)

4. **Run**
   - Press **Cmd+R** or click the ▶ button
   - Look for the **♪ icon** in your menu bar

5. **Play something in Spotify or Apple Music** — the popover will show the current track when you click the icon

---

## Install permanently (survive restarts)

When you run MusicBar for the first time it automatically registers itself as a **Login Item**, so it will relaunch every time you log in.

To make it a proper installed app (not dependent on Xcode):

1. In Xcode: **Product → Archive**
2. In the Organizer: **Distribute App → Copy App**
3. Move the exported `MusicBar.app` to your `/Applications` folder
4. Launch it once from Applications — it will register the login item from its new location

To remove the login item later:  
**System Settings → General → Login Items & Extensions → MusicBar → minus (−)**

---

## How it works

- Uses **Distributed Notifications** (`DistributedNotificationCenter`) to receive track changes from Spotify and Apple Music in real time — no polling for state
- **Spotify transport** (play/pause, skip, previous) goes through the **Spotify Web API** — targeted directly at Spotify, doesn't interfere with other apps
- **Apple Music transport** uses **AppleScript** — targeted directly at the Music app
- Album artwork for Spotify is fetched from the **iTunes Search API** (no account required); Apple Music artwork is fetched via AppleScript from the app itself

---

## Notes

- No App Store — build and run it yourself
- No telemetry
- Network calls: Spotify Web API for transport, iTunes Search API for Spotify album art
- Spotify controls require a one-time OAuth connection (see [Spotify Setup](#spotify-setup) above)
- If album art doesn't load for Spotify, the track wasn't found in the iTunes catalog (rare)

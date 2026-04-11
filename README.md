# MusicBar

A minimal macOS menu bar app that shows what's playing in Spotify or Apple Music.

- Lives in the menu bar — no Dock icon
- Click the icon to see album art, track info, and playback controls
- Supports Spotify and Apple Music (auto-detects whichever is playing)
- Launches automatically at login

---

## Requirements

- macOS 15 or later
- Xcode 16 or later
- A free Apple Developer account (for code signing)
- Spotify and/or Apple Music

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

- Uses **Distributed Notifications** (`DistributedNotificationCenter`) to receive track changes from Spotify and Apple Music in real time — no polling, no AppleScript needed for reading state
- Album artwork is fetched from the **iTunes Search API** (no account or API key required)
- Playback controls simulate **media keys** so they work with any player

---

## Notes

- No App Store — build and run it yourself
- No telemetry, no network calls except fetching album art from iTunes
- If album art doesn't load, it means the track wasn't found in the iTunes catalog (rare)

# ONO Game Setup Guide

## Quick Start

### 1. Install Dependencies

```bash
flutter pub get
cd worker
npm install
```

### 2. Backend Setup (Cloudflare Workers)

1. Create a Cloudflare account and enable Workers + D1
2. Create a D1 database:
   ```bash
   cd worker
   wrangler d1 create ono-db
   ```
3. Update `worker/wrangler.toml` with your database ID
4. Run the schema:
   ```bash
   wrangler d1 execute ono-db --file=../schema.sql
   ```
5. Deploy the worker:
   ```bash
   npm run deploy
   ```
6. Note your worker URL (e.g., `https://ono-worker.your-subdomain.workers.dev`)

### 3. Frontend Setup

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Update `.env` with your configuration:
   ```env
   API_URL=https://uno-aiks-production.pojofiles.workers.dev
   ```

3. Setup app icons (Android):
   - Option 1: Use flutter_launcher_icons package:
     ```bash
     flutter pub add dev:flutter_launcher_icons
     # Add configuration from pubspec_launcher_icons.yaml to pubspec.yaml
     flutter pub run flutter_launcher_icons:main
     ```
   - Option 2: Manually copy `assets/ONO APP LOGO.png` to:
     - `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48)
     - `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72)
     - `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96)
     - `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144)
     - `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192)

4. Run the app:
   ```bash
   flutter run
   ```

## App Icon Setup (Android)

The app name has been set to "ONO" in `android/app/src/main/AndroidManifest.xml`.

To set up app icons:

1. **Using flutter_launcher_icons (Recommended):**
   ```bash
   flutter pub add dev:flutter_launcher_icons
   ```
   Add this to `pubspec.yaml`:
   ```yaml
   dev_dependencies:
     flutter_launcher_icons: ^0.13.1
   
   flutter_launcher_icons:
     android: true
     ios: true
     image_path: "assets/ONO APP LOGO.png"
     min_sdk_android: 21
     adaptive_icon_background: "#0A0A0F"
     adaptive_icon_foreground: "assets/ONO APP LOGO.png"
   ```
   Then run:
   ```bash
   flutter pub run flutter_launcher_icons:main
   ```

2. **Manual Setup:**
   - Resize `assets/ONO APP LOGO.png` to the required sizes
   - Copy to the respective mipmap directories listed above
   - Or use ImageMagick:
     ```bash
     convert "assets/ONO APP LOGO.png" -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
     ```

## WebRTC Voice Chat Setup

The voice chat uses a custom WebRTC implementation with a mesh network topology.

1. **Permissions**: The app requires microphone permission.
2. **STUN Servers**: Google's public STUN servers are used by default (`stun.l.google.com:19302`).
3. **Signaling**: Handled by the custom Cloudflare Worker endpoints (`/rtc/signal` and `/rtc/signals/:playerId`).

**Note:** No external signaling account (like Zego) is required.

## Troubleshooting

### Voice Service Errors

If you encounter audio issues, ensure all players have granted microphone permissions and are on stable network connections. Check the WebRTC logs for "Connection state: failed" or "ICE connection disconnected".

### API Connection Issues

- Ensure your Cloudflare Worker is deployed
- Check that the API_URL in `.env` is correct
- Verify CORS is enabled on your worker if accessing from web

### App Icon Not Showing

- Run `flutter clean` then `flutter pub get`
- Rebuild the app
- Ensure icons are in the correct directories with correct sizes

## Project Structure

- `lib/` - Flutter app source code
  - `models/` - Data models (Card, Player, Room, GameState)
  - `providers/` - State management (RoomProvider, GameProvider)
  - `screens/` - UI screens (Home, Lobby, Game)
  - `services/` - API and voice services
  - `theme/` - App theme
  - `widgets/` - Reusable widgets
- `worker/` - Cloudflare Worker backend
  - `src/` - TypeScript source code
- `assets/` - App assets (logo, font)
- `schema.sql` - Database schema

## Next Steps

1. Deploy your backend worker
2. Set up your `.env` file
3. Configure app icons
4. Test the app on your device

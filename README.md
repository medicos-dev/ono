# ONO - Multiplayer UNO Card Game

A production-ready, real-time multiplayer UNO card game built with Flutter and Cloudflare Workers.

## Features

- 🎮 **Full UNO Game Logic**: Complete implementation of all UNO rules including wild cards, action cards, stacking, and UNO calling
- 👥 **Multiplayer Support**: Support for up to 10 players per room
- 🎤 **Voice Chat**: Push-to-talk voice chat using custom WebRTC Mesh Network
- 🎨 **Dark Theme**: Beautiful dark theme with neon accents
- 🔄 **Real-time Sync**: HTTP polling with long polling fallback for state synchronization
- 🏠 **No Authentication**: Simple player name + room code entry
- 📱 **Cross-Platform**: Built with Flutter for Android, iOS, Web, and Desktop

## Tech Stack

### Frontend
- **Flutter** (latest stable)
- **Provider** (state management)
- **Flutter WebRTC** (voice chat)
- **HTTP** (API communication)

### Backend
- **Cloudflare Workers** (serverless functions)
- **Cloudflare D1** (SQLite database)
- **TypeScript**

## Setup Instructions

### Prerequisites

- Flutter SDK (latest stable)
- Node.js 18+
- Cloudflare account with Workers and D1 enabled

### Backend Setup

1. Navigate to the worker directory:
```bash
cd worker
```

2. Install dependencies:
```bash
npm install
```

3. Create a D1 database:
```bash
wrangler d1 create ono-db
```

4. Update `wrangler.toml` with your database ID:
```toml
[[d1_databases]]
binding = "DB"
database_name = "ono-db"
database_id = "YOUR_DATABASE_ID_HERE"
```

5. Run the database schema:
```bash
wrangler d1 execute ono-db --file=../schema.sql
```

6. Deploy the worker:
```bash
npm run deploy
```

7. Note your worker URL (e.g., `https://ono-worker.your-subdomain.workers.dev`)

### Frontend Setup

1. Copy the environment example file:
```bash
cp .env.example .env
```

```env
API_URL=https://uno-aiks-production.pojofiles.workers.dev
```

3. Install Flutter dependencies:
```bash
flutter pub get
```

4. Run the app:
```bash
flutter run
```

## App Icon and Font Setup

### Android

1. Generate app icons using `flutter_launcher_icons`:
```bash
flutter pub run flutter_launcher_icons:main
```

Or manually replace icons in `android/app/src/main/res/mipmap-*/ic_launcher.png`

2. Update app name in `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:label="ONO"
    ...
```

### iOS

1. Replace app icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

2. Update app name in `ios/Runner/Info.plist`:
```xml
<key>CFBundleDisplayName</key>
<string>ONO</string>
```

## Project Structure

```
ono/
├── lib/
│   ├── models/          # Data models (Card, Player, Room, GameState)
│   ├── providers/       # State management (RoomProvider, GameProvider)
│   ├── screens/         # UI screens (Home, Lobby, Game)
│   ├── services/        # API and voice services
│   ├── theme/           # App theme configuration
│   ├── widgets/         # Reusable widgets
│   └── main.dart        # App entry point
├── worker/
│   └── src/
│       ├── index.ts     # Worker entry point
│       ├── uno-logic.ts # UNO game logic
│       └── types.ts     # TypeScript types
├── schema.sql           # Database schema
└── assets/              # App assets (logo, font)
```

## Game Rules

### Card Play Rules
- Cards can be played if they match the active color OR the type/number matches the top discard card
- Wild cards can always be played (player chooses next color)
- Wild +4 can only be played if player has no matching color card

### Action Cards
- **Skip**: Next player loses their turn
- **Reverse**: Direction toggles (acts like Skip with 2 players)
- **Draw Two (+2)**: Next player draws 2 cards, turn skipped (stackable)
- **Wild**: Player chooses next color
- **Wild Draw Four (+4)**: Next player draws 4 cards, turn skipped (only stackable with another +4)

### UNO Call System
- When a player has exactly 1 card, they must call UNO
- If UNO is not called before the next player plays, the player draws 2 penalty cards
- UNO call is visible to all players with an animated overlay

### Stacking
- +2 cards can be stacked on top of each other
- +4 cards can only be stacked with other +4 cards
- Stacking accumulates the draw count

## API Endpoints

### Room Management
- `POST /room/create` - Create a new room
- `POST /room/join` - Join an existing room
- `POST /room/leave` - Leave a room
- `DELETE /room/:code` - Delete a room (host only)
- `POST /room/resign-host` - Resign as host

### Game Actions
- `POST /game/start` - Start the game (host only)
- `POST /game/play` - Play a card
- `POST /game/draw` - Draw a card
- `POST /game/uno` - Call UNO
- `POST /game/pass` - Pass turn

### State Synchronization
- `POST /sync` - Sync game state (host debounced)
- `GET /poll/:code` - Poll for room updates (long polling)
- `POST /heartbeat` - Update player activity

## Development

### Running in Development Mode

**Backend:**
```bash
cd worker
npm run dev
```

**Frontend:**
```bash
flutter run
```

### Building for Production

**Android:**
```bash
flutter build apk --release
```

**iOS:**
```bash
flutter build ios --release
```

## Troubleshooting

### Common Issues

1. **API URL not working**: Ensure your Cloudflare Worker is deployed and the URL in `.env` is correct
2. **Voice chat not working**: Ensure microphone permissions are granted. WebRTC requires a stable connection between peers.
3. **Database errors**: Make sure the D1 database schema is applied correctly
4. **App icon not showing**: Run `flutter clean` and `flutter pub get`, then rebuild

## License

This project is private and not intended for public distribution.

## Support

For issues or questions, please contact the development team.

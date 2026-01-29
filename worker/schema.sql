CREATE TABLE IF NOT EXISTS rooms (
  code TEXT PRIMARY KEY,
  host_id TEXT NOT NULL,
  status TEXT NOT NULL,
  game_state_json TEXT,
  current_turn_player_id TEXT,
  direction INTEGER NOT NULL DEFAULT 1,
  active_color TEXT NOT NULL,
  pending_draw_count INTEGER NOT NULL DEFAULT 0,
  state_version INTEGER NOT NULL DEFAULT 0,
  last_activity TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS players (
  id TEXT NOT NULL,
  room_code TEXT NOT NULL,
  name TEXT NOT NULL,
  is_host INTEGER NOT NULL DEFAULT 0,
  is_spectator INTEGER DEFAULT 0,
  seat_number INTEGER,
  hand_json TEXT,
  card_count INTEGER DEFAULT 0,
  last_seen TEXT NOT NULL,
  PRIMARY KEY (id, room_code),
  FOREIGN KEY (room_code) REFERENCES rooms(code) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rtc_signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_code TEXT NOT NULL,
  from_player_id TEXT NOT NULL,
  to_player_id TEXT NOT NULL,
  signal_type TEXT NOT NULL,
  signal_data TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (room_code) REFERENCES rooms(code) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rtc_signals_to_player ON rtc_signals(to_player_id, room_code);

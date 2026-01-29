export enum CardColor {
  red = 'red',
  blue = 'blue',
  green = 'green',
  yellow = 'yellow',
  wild = 'wild',
}

export enum CardType {
  number = 'number',
  skip = 'skip',
  reverse = 'reverse',
  drawTwo = 'drawTwo',
  wild = 'wild',
  wildDrawFour = 'wildDrawFour',
}

export interface UnoCard {
  color: CardColor;
  type: CardType;
  number?: number;
  isWild?: boolean;
  isAction?: boolean;
}

export interface Player {
  id: string;
  name: string;
  roomCode: string;
  isHost: boolean;
  isSpectator?: boolean;
  seatNumber?: number;
  hand: UnoCard[];
  lastSeen: string;
}

export enum RoomStatus {
  lobby = 'lobby',
  playing = 'playing',
  finished = 'finished',
}

export enum GameEventType {
  CARD_PLAYED = 'CARD_PLAYED',
  CARD_DRAWN = 'CARD_DRAWN',
  TURN_ADVANCED = 'TURN_ADVANCED',
  UNO_CALLED = 'UNO_CALLED',
  WILD_COLOR_CHOSEN = 'WILD_COLOR_CHOSEN',
  WINNER_DECLARED = 'WINNER_DECLARED',
  ANIMATION_EVENT = 'ANIMATION_EVENT',
  PLAYER_JOINED = 'PLAYER_JOINED',
  PLAYER_LEFT = 'PLAYER_LEFT',
  HOST_CHANGED = 'HOST_CHANGED',
  ROOM_DELETED = 'ROOM_DELETED',
  FORCE_RESYNC = 'FORCE_RESYNC',
}

export interface GameEvent {
  type: GameEventType;
  playerId?: string;
  data?: any;
  timestamp: string;
  eventId: string;
}

export interface GameState {
  drawPile: UnoCard[];
  discardPile: UnoCard[];
  activeColor: CardColor;
  currentTurnPlayerId: string | null;
  direction: number;
  pendingDrawCount: number;
  lastPlayedCardJson: string | null;
  pendingWildColorChoice: string | null;
  unoCalled: Record<string, boolean>;
  stateVersion: number;
  lastActivity: string;
  winnerPlayerId?: string | null;
  winnerTimestamp?: string | null;
  lastPlayedCardAnimationId?: string | null;
  lastEventId?: string | null;
}

export interface Room {
  code: string;
  hostId: string;
  status: RoomStatus;
  gameState: GameState | null;
  players: Player[];
  lastActivity: string;
  stateVersion: number;
  events?: GameEvent[];
}

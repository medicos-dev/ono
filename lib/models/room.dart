import 'dart:convert';
import 'player.dart';
import 'card.dart';

enum RoomStatus {
  lobby,
  playing,
  finished;

  String get name => toString().split('.').last;
}

class GameState {
  final List<UnoCard> drawPile;
  final List<UnoCard> discardPile;
  final CardColor activeColor;
  final String? currentTurnPlayerId;
  final int direction;
  final int pendingDrawCount;
  final String? lastPlayedCardJson;
  final String? pendingWildColorChoice;
  final Map<String, bool> unoCalled;
  final int stateVersion;
  final DateTime lastActivity;
  final String? winnerPlayerId;
  final DateTime? winnerTimestamp;
  final String? lastPlayedCardAnimationId;

  GameState({
    required this.drawPile,
    required this.discardPile,
    required this.activeColor,
    this.currentTurnPlayerId,
    required this.direction,
    required this.pendingDrawCount,
    this.lastPlayedCardJson,
    this.pendingWildColorChoice,
    required this.unoCalled,
    required this.stateVersion,
    required this.lastActivity,
    this.winnerPlayerId,
    this.winnerTimestamp,
    this.lastPlayedCardAnimationId,
  });

  UnoCard? get topDiscardCard {
    if (discardPile.isEmpty) return null;
    if (lastPlayedCardJson != null) {
      try {
        return UnoCard.fromJson(
          Map<String, dynamic>.from(
            Map<String, dynamic>.from(jsonDecode(lastPlayedCardJson!)),
          ),
        );
      } catch (_) {}
    }
    return discardPile.isNotEmpty ? discardPile.last : null;
  }

  bool get isClockwise => direction == 1;

  Map<String, dynamic> toJson() {
    return {
      'drawPile': drawPile.map((c) => c.toJson()).toList(),
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'activeColor': activeColor.name,
      'currentTurnPlayerId': currentTurnPlayerId,
      'direction': direction,
      'pendingDrawCount': pendingDrawCount,
      'lastPlayedCardJson': lastPlayedCardJson,
      'pendingWildColorChoice': pendingWildColorChoice,
      'unoCalled': unoCalled,
      'stateVersion': stateVersion,
      'lastActivity': lastActivity.toIso8601String(),
      'winnerPlayerId': winnerPlayerId,
      'winnerTimestamp': winnerTimestamp?.toIso8601String(),
      'lastPlayedCardAnimationId': lastPlayedCardAnimationId,
    };
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    // Safe null handling - never force cast network data
    final lastActivityStr = json['lastActivity'] as String?;
    final activeColorStr = json['activeColor'] as String?;
    final winnerTimestampStr = json['winnerTimestamp'] as String?;

    return GameState(
      drawPile:
          (json['drawPile'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((c) => UnoCard.fromJson(c))
              .toList() ??
          [],
      discardPile:
          (json['discardPile'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((c) => UnoCard.fromJson(c))
              .toList() ??
          [],
      activeColor: CardColor.values.firstWhere(
        (e) => e.name == (activeColorStr ?? 'red'),
        orElse: () => CardColor.red,
      ),
      currentTurnPlayerId: json['currentTurnPlayerId'] as String?,
      direction: json['direction'] as int? ?? 1,
      pendingDrawCount: json['pendingDrawCount'] as int? ?? 0,
      lastPlayedCardJson: json['lastPlayedCardJson'] as String?,
      pendingWildColorChoice: json['pendingWildColorChoice'] as String?,
      unoCalled:
          json['unoCalled'] != null && json['unoCalled'] is Map
              ? Map<String, bool>.from(
                (json['unoCalled'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v is bool ? v : false),
                ),
              )
              : {},
      stateVersion: json['stateVersion'] as int? ?? 0,
      lastActivity:
          lastActivityStr != null
              ? (DateTime.tryParse(lastActivityStr) ?? DateTime.now())
              : DateTime.now(),
      winnerPlayerId: json['winnerPlayerId'] as String?,
      winnerTimestamp:
          winnerTimestampStr != null
              ? DateTime.tryParse(winnerTimestampStr)
              : null,
      lastPlayedCardAnimationId: json['lastPlayedCardAnimationId'] as String?,
    );
  }

  GameState copyWith({
    List<UnoCard>? drawPile,
    List<UnoCard>? discardPile,
    CardColor? activeColor,
    String? currentTurnPlayerId,
    int? direction,
    int? pendingDrawCount,
    String? lastPlayedCardJson,
    String? pendingWildColorChoice,
    Map<String, bool>? unoCalled,
    int? stateVersion,
    DateTime? lastActivity,
    String? winnerPlayerId,
    DateTime? winnerTimestamp,
    String? lastPlayedCardAnimationId,
  }) {
    return GameState(
      drawPile: drawPile ?? this.drawPile,
      discardPile: discardPile ?? this.discardPile,
      activeColor: activeColor ?? this.activeColor,
      currentTurnPlayerId: currentTurnPlayerId ?? this.currentTurnPlayerId,
      direction: direction ?? this.direction,
      pendingDrawCount: pendingDrawCount ?? this.pendingDrawCount,
      lastPlayedCardJson: lastPlayedCardJson ?? this.lastPlayedCardJson,
      pendingWildColorChoice:
          pendingWildColorChoice ?? this.pendingWildColorChoice,
      unoCalled: unoCalled ?? this.unoCalled,
      stateVersion: stateVersion ?? this.stateVersion,
      lastActivity: lastActivity ?? this.lastActivity,
      winnerPlayerId: winnerPlayerId ?? this.winnerPlayerId,
      winnerTimestamp: winnerTimestamp ?? this.winnerTimestamp,
      lastPlayedCardAnimationId:
          lastPlayedCardAnimationId ?? this.lastPlayedCardAnimationId,
    );
  }
}

enum GameEventType {
  cardPlayed,
  cardDrawn,
  turnAdvanced,
  unoCalled,
  wildColorChosen,
  winnerDeclared,
  animationEvent,
  playerJoined,
  playerLeft,
  hostChanged,
  roomDeleted,
  forceResync;

  String get name => toString().split('.').last.toUpperCase();

  static GameEventType? fromString(String value) {
    try {
      return GameEventType.values.firstWhere(
        (e) => e.name == value.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

class GameEvent {
  final GameEventType type;
  final String? playerId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  final String eventId;

  GameEvent({
    required this.type,
    this.playerId,
    this.data,
    required this.timestamp,
    required this.eventId,
  });

  factory GameEvent.fromJson(Map<String, dynamic> json) {
    // Safe null handling - never force cast network data
    final typeStr = json['type'] as String?;
    final timestampStr = json['timestamp'] as String?;
    final eventId = json['eventId'] as String?;

    return GameEvent(
      type:
          typeStr != null
              ? (GameEventType.fromString(typeStr) ??
                  GameEventType.animationEvent)
              : GameEventType.animationEvent,
      playerId: json['playerId'] as String?,
      data:
          json['data'] != null && json['data'] is Map
              ? Map<String, dynamic>.from(json['data'] as Map)
              : null,
      timestamp:
          timestampStr != null
              ? (DateTime.tryParse(timestampStr) ?? DateTime.now())
              : DateTime.now(),
      eventId: eventId ?? DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  bool get isControlEvent => [
    GameEventType.roomDeleted,
    GameEventType.hostChanged,
    GameEventType.forceResync,
  ].contains(type);
}

class Room {
  final String code;
  final String hostId;
  final RoomStatus status;
  final GameState? gameState;
  final List<Player> players;
  final DateTime lastActivity;
  final List<GameEvent>? events;
  final int stateVersion;

  Room({
    required this.code,
    required this.hostId,
    required this.status,
    this.gameState,
    required this.players,
    required this.lastActivity,
    this.events,
    required this.stateVersion,
  });

  Player? get host =>
      players.firstWhere((p) => p.id == hostId, orElse: () => players.first);

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'hostId': hostId,
      'status': status.name,
      'gameState': gameState?.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
      'lastActivity': lastActivity.toIso8601String(),
      'stateVersion': stateVersion,
      'events':
          events
              ?.map(
                (e) => {
                  'type': e.type.name,
                  'playerId': e.playerId,
                  'data': e.data,
                  'timestamp': e.timestamp.toIso8601String(),
                  'eventId': e.eventId,
                },
              )
              .toList(),
    };
  }

  static List<GameEvent> _parseEventsSafe(dynamic eventsJson) {
    if (eventsJson == null || eventsJson is! List) return [];
    final out = <GameEvent>[];
    for (final e in eventsJson) {
      if (e is! Map<String, dynamic>) continue;
      try {
        out.add(GameEvent.fromJson(e));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  static List<Player> _parsePlayersSafe(dynamic playersJson) {
    if (playersJson == null || playersJson is! List) return [];
    final out = <Player>[];
    for (final p in playersJson) {
      if (p is! Map<String, dynamic>) continue;
      try {
        out.add(Player.fromJson(p));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    // Safe null handling - never force cast network data
    final code = json['code'] as String?;
    final hostId = json['hostId'] as String?;
    final statusStr = json['status'] as String?;
    final lastActivityStr = json['lastActivity'] as String?;

    if (code == null || hostId == null || lastActivityStr == null) {
      throw FormatException(
        'Missing required fields in Room JSON: code=$code, hostId=$hostId, lastActivity=$lastActivityStr',
      );
    }

    return Room(
      code: code,
      hostId: hostId,
      status: RoomStatus.values.firstWhere(
        (e) => e.name == (statusStr ?? 'lobby'),
        orElse: () => RoomStatus.lobby,
      ),
      gameState:
          json['gameState'] != null && json['gameState'] is Map<String, dynamic>
              ? GameState.fromJson(json['gameState'] as Map<String, dynamic>)
              : null,
      players: _parsePlayersSafe(json['players']),
      lastActivity: DateTime.tryParse(lastActivityStr) ?? DateTime.now(),
      stateVersion: json['stateVersion'] as int? ?? 0,
      events: _parseEventsSafe(json['events']),
    );
  }
}

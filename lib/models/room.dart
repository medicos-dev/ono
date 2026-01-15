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
    return GameState(
      drawPile: (json['drawPile'] as List<dynamic>?)
          ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      discardPile: (json['discardPile'] as List<dynamic>?)
          ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      activeColor: CardColor.values.firstWhere(
        (e) => e.name == json['activeColor'],
        orElse: () => CardColor.red,
      ),
      currentTurnPlayerId: json['currentTurnPlayerId'] as String?,
      direction: json['direction'] as int? ?? 1,
      pendingDrawCount: json['pendingDrawCount'] as int? ?? 0,
      lastPlayedCardJson: json['lastPlayedCardJson'] as String?,
      pendingWildColorChoice: json['pendingWildColorChoice'] as String?,
      unoCalled: Map<String, bool>.from(
        json['unoCalled'] as Map<dynamic, dynamic>? ?? {},
      ),
      stateVersion: json['stateVersion'] as int? ?? 0,
      lastActivity: DateTime.parse(json['lastActivity'] as String),
      winnerPlayerId: json['winnerPlayerId'] as String?,
      winnerTimestamp: json['winnerTimestamp'] != null
          ? DateTime.parse(json['winnerTimestamp'] as String)
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
      pendingWildColorChoice: pendingWildColorChoice ?? this.pendingWildColorChoice,
      unoCalled: unoCalled ?? this.unoCalled,
      stateVersion: stateVersion ?? this.stateVersion,
      lastActivity: lastActivity ?? this.lastActivity,
      winnerPlayerId: winnerPlayerId ?? this.winnerPlayerId,
      winnerTimestamp: winnerTimestamp ?? this.winnerTimestamp,
      lastPlayedCardAnimationId: lastPlayedCardAnimationId ?? this.lastPlayedCardAnimationId,
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
    return GameEvent(
      type: GameEventType.fromString(json['type'] as String) ?? GameEventType.animationEvent,
      playerId: json['playerId'] as String?,
      data: json['data'] != null ? Map<String, dynamic>.from(json['data'] as Map) : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
      eventId: json['eventId'] as String,
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

  Room({
    required this.code,
    required this.hostId,
    required this.status,
    this.gameState,
    required this.players,
    required this.lastActivity,
    this.events,
  });

  Player? get host => players.firstWhere((p) => p.id == hostId, orElse: () => players.first);

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'hostId': hostId,
      'status': status.name,
      'gameState': gameState?.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
      'lastActivity': lastActivity.toIso8601String(),
      'events': events?.map((e) => {
        'type': e.type.name,
        'playerId': e.playerId,
        'data': e.data,
        'timestamp': e.timestamp.toIso8601String(),
        'eventId': e.eventId,
      }).toList(),
    };
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      code: json['code'] as String,
      hostId: json['hostId'] as String,
      status: RoomStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RoomStatus.lobby,
      ),
      gameState: json['gameState'] != null
          ? GameState.fromJson(json['gameState'] as Map<String, dynamic>)
          : null,
      players: (json['players'] as List<dynamic>?)
          ?.map((p) => Player.fromJson(p as Map<String, dynamic>))
          .toList() ?? [],
      lastActivity: DateTime.parse(json['lastActivity'] as String),
      events: json['events'] != null
          ? (json['events'] as List<dynamic>)
              .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

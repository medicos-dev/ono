import 'card.dart';

class Player {
  final String id;
  final String name;
  final String roomCode;
  final bool isHost;
  final bool isSpectator;
  final int? seatNumber;
  final List<UnoCard> hand;
  final DateTime lastSeen;

  Player({
    required this.id,
    required this.name,
    required this.roomCode,
    required this.isHost,
    this.isSpectator = false,
    this.seatNumber,
    required this.hand,
    required this.lastSeen,
  });

  int get cardCount => hand.length;
  
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length > 1 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roomCode': roomCode,
      'isHost': isHost,
      'isSpectator': isSpectator,
      'seatNumber': seatNumber,
      'hand': hand.map((c) => c.toJson()).toList(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    // Safe null handling - never force cast network data
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final roomCode = json['roomCode'] as String?;
    final lastSeenStr = json['lastSeen'] as String?;
    
    if (id == null || name == null || roomCode == null || lastSeenStr == null) {
      throw FormatException('Missing required fields in Player JSON: id=$id, name=$name, roomCode=$roomCode, lastSeen=$lastSeenStr');
    }
    
    return Player(
      id: id,
      name: name,
      roomCode: roomCode,
      isHost: json['isHost'] as bool? ?? false,
      isSpectator: json['isSpectator'] as bool? ?? false,
      seatNumber: json['seatNumber'] as int?,
      hand: (json['hand'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((c) => UnoCard.fromJson(c))
          .toList() ?? [],
      lastSeen: DateTime.tryParse(lastSeenStr) ?? DateTime.now(),
    );
  }

  Player copyWith({
    String? id,
    String? name,
    String? roomCode,
    bool? isHost,
    bool? isSpectator,
    int? seatNumber,
    List<UnoCard>? hand,
    DateTime? lastSeen,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      roomCode: roomCode ?? this.roomCode,
      isHost: isHost ?? this.isHost,
      isSpectator: isSpectator ?? this.isSpectator,
      seatNumber: seatNumber ?? this.seatNumber,
      hand: hand ?? this.hand,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

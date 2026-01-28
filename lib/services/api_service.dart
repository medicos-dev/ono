import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/room.dart';
import '../models/card.dart';

class RoomDeletedException implements Exception {
  final String reason;
  final List<GameEvent> events;

  RoomDeletedException({required this.reason, required this.events});

  @override
  String toString() => 'Room deleted: $reason';
}

class ApiService {
  String? baseUrl;

  void initialize(String url) {
    baseUrl = url;
  }

  String get _baseUrl {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('API base URL not initialized. Set it in .env file.');
    }
    return baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
  }

  Future<Room> createRoom(String playerName, String playerId, String roomCode) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/room/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playerName': playerName,
        'playerId': playerId,
        'roomCode': roomCode.toUpperCase(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create room: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> joinRoom(String roomCode, String playerName, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/room/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerName': playerName,
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      final error = body?['error'] as String? ?? response.body;
      throw Exception('Failed to join room: $error');
    }

    // Join response is ACK only - do NOT parse as Room
    // Client must wait for /poll to receive full room snapshot
    final body = jsonDecode(response.body) as Map<String, dynamic>?;
    if (body?['success'] != true && body?['error'] != null) {
      throw Exception('Failed to join room: ${body!['error']}');
    }
  }

  Future<void> leaveRoom(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/room/leave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to leave room: ${response.body}');
    }
  }

  Future<Room> resignHost(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/room/resign-host'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to resign host: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> startGame(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/game/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to start game: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> playCard(
    String roomCode,
    String playerId,
    UnoCard card,
    CardColor? chosenColor,
  ) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/game/play'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
        'card': card.toJson(),
        'chosenColor': chosenColor?.name,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to play card: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> drawCard(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/game/draw'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to draw card: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> callUno(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/game/uno'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to call UNO: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> passTurn(String roomCode, String playerId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/game/pass'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to pass turn: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room> syncGame(String roomCode, String playerId, int stateVersion) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/sync'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roomCode': roomCode.toUpperCase(),
        'playerId': playerId,
        'stateVersion': stateVersion,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to sync game: ${response.body}');
    }

    return Room.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Room?> pollRoom(String roomCode, {int? lastKnownVersion, bool isSpectator = false}) async {
    final params = <String, String>{};
    if (lastKnownVersion != null) {
      params['lastKnownVersion'] = lastKnownVersion.toString();
    }
    if (isSpectator) {
      params['isSpectator'] = 'true';
    }
    
    final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final url = '$_baseUrl/poll/${roomCode.toUpperCase()}${queryString.isNotEmpty ? '?$queryString' : ''}';
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 304 || response.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      
      if (body['changed'] == false) {
        return null;
      }

      // Check for ROOM_DELETED event
      if (body['type'] == 'ROOM_DELETED') {
        throw RoomDeletedException(
          reason: body['reason'] as String? ?? 'UNKNOWN',
          events: body['events'] != null
              ? (body['events'] as List<dynamic>)
                  .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
                  .toList()
              : [],
        );
      }

      if (body.containsKey('error') && body['error'] == 'Room not found') {
        throw RoomDeletedException(reason: 'NOT_FOUND', events: []);
      }

      return Room.fromJson(body);
    } catch (e) {
      if (e is RoomDeletedException) {
        rethrow;
      }
      return null;
    }
  }

  Future<void> sendHeartbeat(String roomCode, String playerId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomCode': roomCode.toUpperCase(),
          'playerId': playerId,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
    }
  }
}

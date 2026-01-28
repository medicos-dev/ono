// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: undefined_getter

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../models/isar_models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/isar_service.dart';
import '../services/voice_service.dart';

class RoomProvider with ChangeNotifier {
  Room? _room;
  Player? _currentPlayer;
  String? _error;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  bool _isPolling = false;
  int _lastNotifiedVersion = 0;
  StreamSubscription<Room>? _isarSubscription;

  Room? get room => _room;
  Player? get currentPlayer => _currentPlayer;
  String? get error => _error;
  bool get isPolling => _isPolling;

  bool get isHost => _currentPlayer?.isHost ?? false;
  String? get roomCode => _room?.code;
  bool get isPlaying => _room?.status == RoomStatus.playing;
  bool get isInLobby => _room?.status == RoomStatus.lobby;

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  final ApiService _apiService = ApiService();

  Future<void> createRoom(String playerName, String playerId, String roomCode) async {
    try {
      _error = null;
      if (_apiService.baseUrl == null || _apiService.baseUrl!.isEmpty) {
        throw Exception('API base URL not initialized. Please check your .env file and restart the app.');
      }
      // Clear any stale cache for this room
      await IsarService.clearRoomData(roomCode.toUpperCase());
      final room = await _apiService.createRoom(playerName, playerId, roomCode);
      await IsarService.writeRoomSnapshot(room);
      _room = await IsarService.getCachedRoom(room.code);
      if (_room != null) {
        _currentPlayer = _room!.players.firstWhere((p) => p.id == playerId);
      }
      await StorageService.savePlayerName(playerName);
      await StorageService.saveRoomCode(room.code);
      _startPolling();
      _startHeartbeat();
      _subscribeToIsarUpdates(room.code);
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> joinRoom(String roomCode, String playerName, String playerId) async {
    try {
      _error = null;
      if (_apiService.baseUrl == null || _apiService.baseUrl!.isEmpty) {
        throw Exception('API base URL not initialized. Please check your .env file and restart the app.');
      }
      
      // Clear any stale cache for this room before joining
      await IsarService.clearRoomData(roomCode.toUpperCase());
      
      // Join room - response is ACK only, do NOT parse room data
      await _apiService.joinRoom(roomCode.toUpperCase(), playerName, playerId);

      // Save player name and room code for polling
      await StorageService.savePlayerName(playerName);
      await StorageService.saveRoomCode(roomCode.toUpperCase());

      // Perform an initial full poll to get the authoritative room snapshot
      final joinedRoom = await _apiService.pollRoom(
        roomCode.toUpperCase(),
        lastKnownVersion: 0,
        isSpectator: false,
      );

      if (joinedRoom == null) {
        throw Exception('Failed to load room state after join. Please try again.');
      }

      // Persist and hydrate local room state from the polled snapshot
      await IsarService.writeRoomSnapshot(joinedRoom);
      final cachedRoom = await IsarService.getCachedRoom(joinedRoom.code);
      if (cachedRoom != null) {
        _room = cachedRoom;
        try {
          _currentPlayer = cachedRoom.players.firstWhere(
            (p) => p.id == playerId,
          );
        } catch (_) {
          // If player not found in snapshot, treat as fatal for this join
          throw Exception('Joined room but player is missing from room snapshot.');
        }
      }

      // Start ongoing polling and heartbeat after we have a valid room snapshot
      _startPolling();
      _startHeartbeat();
      _subscribeToIsarUpdates(joinedRoom.code);

      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> leaveRoom() async {
    if (_room == null || _currentPlayer == null) return;

    final roomCode = _room!.code;
    final playerId = _currentPlayer!.id;

    stopPolling();
    _stopHeartbeat();
    _isarSubscription?.cancel();
    _isarSubscription = null;
    _room = null;
    _currentPlayer = null;
    notifyListeners();

    try {
      await _apiService.leaveRoom(roomCode, playerId);
      await StorageService.clearRoomCode();
      await IsarService.clearRoomData(roomCode);
    } catch (e) {
    }
  }

  void _subscribeToIsarUpdates(String roomCode) {
    _isarSubscription?.cancel();
    _isarSubscription = IsarService.watchRoom(roomCode).listen((room) {
      _room = room;
      if (_currentPlayer != null) {
        _currentPlayer = room.players.firstWhere(
          (p) => p.id == _currentPlayer!.id,
          orElse: () => _currentPlayer!,
        );
      }
      notifyListeners();
    });
  }

  Future<void> resignHost() async {
    if (_room == null || _currentPlayer == null || !isHost) return;

    try {
      _error = null;
      _room = await _apiService.resignHost(_room!.code, _currentPlayer!.id);
      _currentPlayer = _room!.players.firstWhere((p) => p.id == _currentPlayer!.id);
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startGame() async {
    if (_room == null || _currentPlayer == null || !isHost) return;

    try {
      _error = null;
      _room = await _apiService.startGame(_room!.code, _currentPlayer!.id);
      _currentPlayer = _room!.players.firstWhere((p) => p.id == _currentPlayer!.id);
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> initializeApi(String url) async {
    _apiService.initialize(url);
    
    final savedRoomCode = await StorageService.getRoomCode();
    if (savedRoomCode != null && savedRoomCode.isNotEmpty) {
      final cachedRoom = await IsarService.getCachedRoom(savedRoomCode);
      if (cachedRoom != null) {
        final metadata = await IsarService.instance.syncMetadatas
            .filter()
            .roomCodeEqualTo(savedRoomCode)
            .findFirst();
        
        if (metadata?.needsFullSync == true) {
          await IsarService.markNeedsFullSync(savedRoomCode);
        }
      }
    }
  }

  Future<void> updateRoom() async {
    if (_room == null || _currentPlayer == null) {
      stopPolling();
      return;
    }

    try {
      final metadata = await IsarService.instance.syncMetadatas
          .filter()
          .roomCodeEqualTo(_room!.code)
          .findFirst();

      if (metadata?.needsFullSync == true) {
        await _performFullSync();
        return;
      }

      final lastVersion = _room!.gameState?.stateVersion ?? 0;
      final isSpectator = _currentPlayer!.isSpectator;
      final updatedRoom = await _apiService.pollRoom(
        _room!.code, 
        lastKnownVersion: lastVersion,
        isSpectator: isSpectator,
      );
      
      if (updatedRoom != null) {
        if (updatedRoom.code != _room!.code) {
          await leaveRoom();
          return;
        }

        final newVersion = updatedRoom.gameState?.stateVersion ?? 0;
        final playersChanged = updatedRoom.players.length != _room!.players.length;
        final statusChanged = updatedRoom.status != _room!.status;
        final hasEvents = updatedRoom.events != null && updatedRoom.events!.isNotEmpty;
        
        if (newVersion > lastVersion || playersChanged || statusChanged || hasEvents) {
          await IsarService.writeRoomSnapshot(updatedRoom);
          final cachedRoom = await IsarService.getCachedRoom(updatedRoom.code);
          if (cachedRoom != null) {
            _room = cachedRoom;
            if (_currentPlayer != null) {
              _currentPlayer = cachedRoom.players.firstWhere(
                (p) => p.id == _currentPlayer!.id,
                orElse: () => _currentPlayer!,
              );
            }
            if (newVersion > _lastNotifiedVersion || playersChanged || statusChanged || hasEvents) {
              _lastNotifiedVersion = newVersion;
              notifyListeners();
            }
          }
        }
      }
    } on RoomDeletedException catch (e) {
      await _handleRoomDeleted(e.reason);
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('room not found') || 
          errorMessage.contains('not found') ||
          errorMessage.contains('404') ||
          errorMessage.contains('room deleted')) {
        await _handleRoomDeleted('NOT_FOUND');
        return;
      }
    }
  }

  Future<void> _performFullSync() async {
    if (_room == null || _currentPlayer == null) return;

    try {
      final updatedRoom = await _apiService.pollRoom(_room!.code, lastKnownVersion: 0);
      if (updatedRoom != null) {
        await IsarService.writeRoomSnapshot(updatedRoom);
        await IsarService.clearPendingEvents(_room!.code);
        final metadata = await IsarService.instance.syncMetadatas
            .filter()
            .roomCodeEqualTo(_room!.code)
            .findFirst();
        if (metadata != null) {
          metadata.needsFullSync = false;
          await IsarService.instance.syncMetadatas.put(metadata);
        }
        final cachedRoom = await IsarService.getCachedRoom(updatedRoom.code);
        if (cachedRoom != null) {
          _room = cachedRoom;
          if (_currentPlayer != null) {
            _currentPlayer = cachedRoom.players.firstWhere(
              (p) => p.id == _currentPlayer!.id,
              orElse: () => _currentPlayer!,
            );
          }
          notifyListeners();
        }
      }
    } on RoomDeletedException catch (e) {
      await _handleRoomDeleted(e.reason);
    } catch (e) {
      await IsarService.markNeedsFullSync(_room!.code);
    }
  }

  Future<void> _handleRoomDeleted(String reason) async {
    final roomCode = _room?.code;
    
    stopPolling();
    _stopHeartbeat();
    _isarSubscription?.cancel();
    _isarSubscription = null;
    
    if (roomCode != null) {
      await VoiceService.leaveRoom();
      await IsarService.clearRoomData(roomCode);
      await StorageService.clearRoomCode();
    }
    
    _room = null;
    _currentPlayer = null;
    _error = reason == 'HOST_LEFT' 
        ? 'Host left the room. Returning to home.'
        : 'Room was deleted. Returning to home.';
    notifyListeners();
  }

  void _startPolling() {
    stopPolling();
    _isPolling = true;
    final isSpectator = _currentPlayer?.isSpectator ?? false;
    final pollInterval = isSpectator ? const Duration(seconds: 8) : const Duration(seconds: 2);
    _pollTimer = Timer.periodic(pollInterval, (_) {
      updateRoom();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
  }

  void startPolling() {
    _startPolling();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_room != null && _currentPlayer != null) {
        _apiService.sendHeartbeat(_room!.code, _currentPlayer!.id);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> updateRoomState(Room room) async {
    await IsarService.writeRoomSnapshot(room);
    final cachedRoom = await IsarService.getCachedRoom(room.code);
    if (cachedRoom != null) {
      final newVersion = cachedRoom.gameState?.stateVersion ?? 0;
      if (newVersion > _lastNotifiedVersion || 
          _room == null ||
          cachedRoom.players.length != _room!.players.length ||
          cachedRoom.status != _room!.status) {
        _room = cachedRoom;
        if (_currentPlayer != null) {
          _currentPlayer = cachedRoom.players.firstWhere(
            (p) => p.id == _currentPlayer!.id,
            orElse: () => _currentPlayer!,
          );
        }
        _lastNotifiedVersion = newVersion;
        notifyListeners();
      } else {
        _room = cachedRoom;
        if (_currentPlayer != null) {
          _currentPlayer = cachedRoom.players.firstWhere(
            (p) => p.id == _currentPlayer!.id,
            orElse: () => _currentPlayer!,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    stopPolling();
    _stopHeartbeat();
    _isarSubscription?.cancel();
    _isarSubscription = null;
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../providers/room_provider.dart';
import '../services/webrtc_service.dart';

class GameProvider with ChangeNotifier {
  final RoomProvider roomProvider;
  final ApiService _apiService = ApiService();
  bool _isProcessingAction = false;
  String? _actionError;
  UnoCard? _selectedCard;
  CardColor? _pendingColorChoice;
  bool _isMicOn = false;

  GameProvider(this.roomProvider);

  bool get isMicOn => _isMicOn;

  bool get isProcessingAction => _isProcessingAction;
  String? get actionError => _actionError;
  UnoCard? get selectedCard => _selectedCard;
  CardColor? get pendingColorChoice => _pendingColorChoice;

  Room? get room => roomProvider.room;
  GameState? get gameState => room?.gameState;
  Player? get currentPlayer => roomProvider.currentPlayer;

  bool get isMyTurn {
    if (gameState == null || currentPlayer == null) return false;
    return gameState!.currentTurnPlayerId == currentPlayer!.id;
  }

  bool get canPlayCard {
    if (!isMyTurn || _isProcessingAction) return false;
    if (gameState == null || currentPlayer == null) return false;
    if (gameState!.pendingDrawCount > 0 && !_canStack()) return false;
    if (_selectedCard == null) return false;

    final topCard = gameState!.topDiscardCard;
    if (topCard == null) return false;

    return _selectedCard!.canPlayOn(topCard, gameState!.activeColor);
  }

  bool get canDrawCard {
    if (!isMyTurn || _isProcessingAction) return false;
    if (gameState == null) return false;
    return true;
  }

  bool get canPassTurn {
    if (!isMyTurn || _isProcessingAction) return false;
    if (gameState == null || currentPlayer == null) return false;
    if (gameState!.pendingDrawCount > 0) return false;
    return true;
  }

  bool get canCallUno {
    if (_isProcessingAction) return false;
    if (currentPlayer == null || gameState == null) return false;
    if (currentPlayer!.cardCount != 1) return false;
    if (gameState!.unoCalled[currentPlayer!.id] == true) return false;
    return true;
  }

  bool _canStack() {
    if (gameState == null || currentPlayer == null) return false;
    if (gameState!.pendingDrawCount == 0) return true;
    if (gameState!.pendingDrawCount % 2 != 0) return false;

    final topCard = gameState!.topDiscardCard;
    if (topCard == null || topCard.type != CardType.drawTwo) return false;

    if (gameState!.pendingDrawCount >= 8) {
      return currentPlayer!.hand.any((c) => c.type == CardType.wildDrawFour);
    }

    return currentPlayer!.hand.any(
      (c) => c.type == CardType.drawTwo && c.color == gameState!.activeColor,
    );
  }

  void selectCard(UnoCard card) {
    if (!isMyTurn || _isProcessingAction) return;
    _selectedCard = card;
    _actionError = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedCard = null;
    _pendingColorChoice = null;
    _actionError = null;
    notifyListeners();
  }

  void setColorChoice(CardColor color) {
    _pendingColorChoice = color;
    notifyListeners();
  }

  Future<void> playCard(UnoCard card, {CardColor? chosenColor}) async {
    if (_isProcessingAction || !isMyTurn) return;
    if (room == null || currentPlayer == null) return;

    final eventId =
        '${currentPlayer!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final currentVersion = gameState?.stateVersion ?? 0;

    try {
      _isProcessingAction = true;
      _actionError = null;
      notifyListeners();

      final optimisticHand = List<UnoCard>.from(currentPlayer!.hand)
        ..remove(card);
      final optimisticDiscard = List<UnoCard>.from(gameState!.discardPile)
        ..add(card);
      final optimisticState = gameState!.copyWith(
        discardPile: optimisticDiscard,
        stateVersion: currentVersion + 1,
        lastActivity: DateTime.now(),
        activeColor: chosenColor ?? card.color,
      );
      final optimisticRoom = Room(
        code: room!.code,
        hostId: room!.hostId,
        status: room!.status,
        gameState: optimisticState,
        players:
            room!.players.map((p) {
              if (p.id == currentPlayer!.id) {
                return p.copyWith(hand: optimisticHand);
              }
              return p;
            }).toList(),
        lastActivity: DateTime.now(),
      );

      await IsarService.writeRoomSnapshot(optimisticRoom, isOptimistic: true);
      await IsarService.addEvent(
        room!.code,
        eventId,
        currentVersion + 1,
        'CARD_PLAYED',
        playerId: currentPlayer!.id,
        payload: jsonEncode(card.toJson()),
        isPending: true,
      );

      final updatedRoom = await _apiService.playCard(
        room!.code,
        currentPlayer!.id,
        card,
        chosenColor ?? _pendingColorChoice,
      );

      await IsarService.writeRoomSnapshot(updatedRoom);
      await IsarService.markEventApplied(eventId);
      await IsarService.clearPendingEvents(room!.code);
      await roomProvider.updateRoomState(updatedRoom);
      _selectedCard = null;
      _pendingColorChoice = null;
      _isProcessingAction = false;
      notifyListeners();
    } catch (e) {
      final cachedRoom = await IsarService.getCachedRoom(room!.code);
      if (cachedRoom != null) {
        await roomProvider.updateRoomState(cachedRoom);
      }
      await IsarService.clearPendingEvents(room!.code);
      _isProcessingAction = false;
      _actionError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> drawCard() async {
    if (_isProcessingAction || !isMyTurn) return;
    if (room == null || currentPlayer == null) return;

    final eventId =
        '${currentPlayer!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final currentVersion = gameState?.stateVersion ?? 0;

    try {
      _isProcessingAction = true;
      _actionError = null;
      notifyListeners();

      final updatedRoom = await _apiService.drawCard(
        room!.code,
        currentPlayer!.id,
      );

      await IsarService.writeRoomSnapshot(updatedRoom);
      await IsarService.addEvent(
        room!.code,
        eventId,
        updatedRoom.gameState?.stateVersion ?? currentVersion + 1,
        'CARD_DRAWN',
        playerId: currentPlayer!.id,
      );
      await IsarService.markEventApplied(eventId);
      await roomProvider.updateRoomState(updatedRoom);
      _selectedCard = null;
      _isProcessingAction = false;
      notifyListeners();
    } catch (e) {
      final cachedRoom = await IsarService.getCachedRoom(room!.code);
      if (cachedRoom != null) {
        await roomProvider.updateRoomState(cachedRoom);
      }
      _isProcessingAction = false;
      _actionError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> callUno() async {
    if (_isProcessingAction || !canCallUno) return;
    if (room == null || currentPlayer == null) return;

    final eventId =
        '${currentPlayer!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final currentVersion = gameState?.stateVersion ?? 0;

    try {
      _isProcessingAction = true;
      _actionError = null;
      notifyListeners();

      final updatedRoom = await _apiService.callUno(
        room!.code,
        currentPlayer!.id,
      );

      await IsarService.writeRoomSnapshot(updatedRoom);
      await IsarService.addEvent(
        room!.code,
        eventId,
        updatedRoom.gameState?.stateVersion ?? currentVersion + 1,
        'UNO_CALLED',
        playerId: currentPlayer!.id,
      );
      await IsarService.markEventApplied(eventId);
      await roomProvider.updateRoomState(updatedRoom);
      _isProcessingAction = false;
      notifyListeners();
    } catch (e) {
      final cachedRoom = await IsarService.getCachedRoom(room!.code);
      if (cachedRoom != null) {
        await roomProvider.updateRoomState(cachedRoom);
      }
      _isProcessingAction = false;
      _actionError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> passTurn() async {
    if (_isProcessingAction || !isMyTurn) return;
    if (room == null || currentPlayer == null) return;

    final eventId =
        '${currentPlayer!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final currentVersion = gameState?.stateVersion ?? 0;

    try {
      _isProcessingAction = true;
      _actionError = null;
      notifyListeners();

      final updatedRoom = await _apiService.passTurn(
        room!.code,
        currentPlayer!.id,
      );

      await IsarService.writeRoomSnapshot(updatedRoom);
      await IsarService.addEvent(
        room!.code,
        eventId,
        updatedRoom.gameState?.stateVersion ?? currentVersion + 1,
        'TURN_ADVANCED',
        playerId: currentPlayer!.id,
      );
      await IsarService.markEventApplied(eventId);
      await roomProvider.updateRoomState(updatedRoom);
      _selectedCard = null;
      _isProcessingAction = false;
      notifyListeners();
    } catch (e) {
      final cachedRoom = await IsarService.getCachedRoom(room!.code);
      if (cachedRoom != null) {
        await roomProvider.updateRoomState(cachedRoom);
      }
      _isProcessingAction = false;
      _actionError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void clearActionError() {
    _actionError = null;
    notifyListeners();
  }

  Future<void> toggleMic(bool isOn) async {
    await WebRTCService().toggleMic(isOn);
    _isMicOn = isOn;
    notifyListeners();
  }
}

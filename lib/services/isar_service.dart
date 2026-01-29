// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: undefined_class
// ignore_for_file: undefined_getter

import 'dart:async';
import 'dart:convert';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_models.dart' as isar_models;
import '../models/room.dart';
import '../models/card.dart';
import '../models/player.dart';

class IsarService {
  static Isar? _isar;
  static final Map<String, StreamController<Room>> _roomStreams = {};

  static Future<void> initialize() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open([
      isar_models.GameStateSnapshotSchema,
      isar_models.DiscardPileCardSchema,
      isar_models.PlayerSnapshotSchema,
      isar_models.PlayerHandSchema,
      isar_models.GameEventSchema,
      isar_models.SyncMetadataSchema,
    ], directory: dir.path);
  }

  static Isar get instance {
    if (_isar == null) {
      throw StateError(
        'Isar not initialized. Call IsarService.initialize() first.',
      );
    }
    return _isar!;
  }

  static Future<void> close() async {
    for (final controller in _roomStreams.values) {
      await controller.close();
    }
    _roomStreams.clear();
    await _isar?.close();
    _isar = null;
  }

  static Stream<Room> watchRoom(String roomCode) {
    if (!_roomStreams.containsKey(roomCode)) {
      _roomStreams[roomCode] = StreamController<Room>.broadcast();
    }
    return _roomStreams[roomCode]!.stream;
  }

  static Future<Room?> getCachedRoom(String roomCode) async {
    try {
      final snapshot =
          await instance.gameStateSnapshots
              .filter()
              .roomCodeEqualTo(roomCode)
              .findFirst();

      if (snapshot == null) return null;

      final players =
          await instance.playerSnapshots
              .filter()
              .roomCodeEqualTo(roomCode)
              .findAll();

      final discardPile =
          await instance.discardPileCards
              .filter()
              .roomCodeEqualTo(roomCode)
              .sortByCardIndex()
              .findAll();

      final hands =
          await instance.playerHands
              .filter()
              .roomCodeEqualTo(roomCode)
              .findAll();

      final discardCards =
          discardPile
              .map((dp) {
                try {
                  return UnoCard(
                    color: CardColor.values.firstWhere(
                      (e) => e.name == dp.color,
                      orElse: () => CardColor.wild,
                    ),
                    type: CardType.values.firstWhere(
                      (e) => e.name == dp.type,
                      orElse: () => CardType.number,
                    ),
                    number: dp.number,
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<UnoCard>()
              .toList();

      final playerList = <Player>[];
      for (final ps in players) {
        final handData = hands.firstWhere(
          (h) => h.playerId == ps.playerId,
          orElse:
              () =>
                  isar_models.PlayerHand()
                    ..playerId = ps.playerId
                    ..roomCode = roomCode
                    ..cardData = []
                    ..lastUpdated = DateTime.now(),
        );

        final hand =
            handData.cardData
                .map((cardJson) {
                  try {
                    final cardMap =
                        jsonDecode(cardJson) as Map<String, dynamic>;
                    return UnoCard.fromJson(cardMap);
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<UnoCard>()
                .toList();

        playerList.add(
          Player(
            id: ps.playerId,
            name: ps.name,
            roomCode: roomCode,
            isHost: ps.isHost,
            isSpectator: ps.isSpectator,
            seatNumber: ps.seatNumber,
            hand: hand,
            lastSeen: ps.lastUpdated,
          ),
        );
      }

      final roomStatus = RoomStatus.values.firstWhere(
        (e) => e.name == snapshot.roomStatus,
        orElse: () => RoomStatus.lobby,
      );

      GameState? gameState;
      if (roomStatus == RoomStatus.playing) {
        gameState = GameState(
          drawPile: List.filled(
            snapshot.drawPileCount,
            UnoCard(color: CardColor.wild, type: CardType.wild),
          ),
          discardPile: discardCards,
          activeColor: CardColor.values.firstWhere(
            (e) => e.name == snapshot.activeColor,
            orElse: () => CardColor.red,
          ),
          currentTurnPlayerId: snapshot.currentTurnPlayerId,
          direction: snapshot.direction,
          pendingDrawCount: snapshot.pendingDrawCount,
          unoCalled: {},
          stateVersion: snapshot.stateVersion,
          lastActivity: snapshot.lastUpdated,
          winnerPlayerId: snapshot.winnerPlayerId,
          winnerTimestamp: snapshot.winnerTimestamp,
          lastPlayedCardAnimationId: snapshot.lastPlayedCardAnimationId,
        );
      }

      return Room(
        code: roomCode,
        hostId:
            playerList
                .firstWhere((p) => p.isHost, orElse: () => playerList.first)
                .id,
        status: roomStatus,
        gameState: gameState,
        players: playerList,
        lastActivity: snapshot.lastUpdated,
        stateVersion: snapshot.stateVersion,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<bool> writeRoomSnapshot(
    Room room, {
    bool isOptimistic = false,
  }) async {
    try {
      // Process control events first - they bypass version checks
      if (room.events != null && room.events!.isNotEmpty) {
        final controlEvents =
            room.events!.where((e) => e.isControlEvent).toList();
        if (controlEvents.isNotEmpty) {
          for (final event in controlEvents) {
            if (event.type == GameEventType.roomDeleted) {
              await clearRoomData(room.code);
              return true;
            } else if (event.type == GameEventType.forceResync) {
              await markNeedsFullSync(room.code);
            }
          }
        }
      }

      final metadata =
          await instance.syncMetadatas
              .filter()
              .roomCodeEqualTo(room.code)
              .findFirst();

      final currentVersion = metadata?.lastAppliedStateVersion ?? 0;
      final incomingVersion = room.gameState?.stateVersion ?? 0;

      // Control events bypass version checks, but regular updates don't
      final hasControlEvents =
          room.events?.any((e) => e.isControlEvent) ?? false;
      if (incomingVersion < currentVersion &&
          !isOptimistic &&
          !hasControlEvents) {
        return false;
      }

      await instance.writeTxn(() async {
        final snapshot =
            isar_models.GameStateSnapshot()
              ..roomCode = room.code
              ..stateVersion = incomingVersion
              ..currentTurnPlayerId = room.gameState?.currentTurnPlayerId
              ..direction = room.gameState?.direction ?? 1
              ..activeColor = room.gameState?.activeColor.name ?? 'red'
              ..pendingDrawCount = room.gameState?.pendingDrawCount ?? 0
              ..drawPileCount = room.gameState?.drawPile.length ?? 0
              ..lastUpdated = DateTime.now()
              ..winnerPlayerId = room.gameState?.winnerPlayerId
              ..winnerTimestamp = room.gameState?.winnerTimestamp
              ..lastPlayedCardAnimationId =
                  room.gameState?.lastPlayedCardAnimationId
              ..roomStatus = room.status.name;

        await instance.gameStateSnapshots.put(snapshot);

        await instance.discardPileCards
            .filter()
            .roomCodeEqualTo(room.code)
            .deleteAll();

        if (room.gameState != null) {
          final discardCards =
              room.gameState!.discardPile.asMap().entries.map((e) {
                return isar_models.DiscardPileCard()
                  ..roomCode = room.code
                  ..cardIndex = e.key
                  ..color = e.value.color.name
                  ..type = e.value.type.name
                  ..number = e.value.number
                  ..addedAt = DateTime.now();
              }).toList();

          await instance.discardPileCards.putAll(discardCards);
        }

        for (final player in room.players) {
          final ps =
              isar_models.PlayerSnapshot()
                ..roomCode = room.code
                ..playerId = player.id
                ..name = player.name
                ..isHost = player.isHost
                ..isSpectator = player.isSpectator
                ..seatNumber = player.seatNumber
                ..cardCount = player.cardCount
                ..lastUpdated = DateTime.now();

          await instance.playerSnapshots.put(ps);

          final hand =
              isar_models.PlayerHand()
                ..playerId = player.id
                ..roomCode = room.code
                ..cardData =
                    player.hand.map((c) => jsonEncode(c.toJson())).toList()
                ..lastUpdated = DateTime.now();

          await instance.playerHands.put(hand);
        }

        final syncMeta =
            isar_models.SyncMetadata()
              ..roomCode = room.code
              ..lastAppliedStateVersion = incomingVersion
              ..lastSyncAt = DateTime.now()
              ..needsFullSync = false;

        await instance.syncMetadatas.put(syncMeta);
      });

      final cachedRoom = await getCachedRoom(room.code);
      if (cachedRoom != null && _roomStreams.containsKey(room.code)) {
        _roomStreams[room.code]!.add(cachedRoom);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> addEvent(
    String roomCode,
    String eventId,
    int stateVersion,
    String eventType, {
    String? playerId,
    String? payload,
    bool isPending = false,
  }) async {
    try {
      final event =
          isar_models.GameEvent()
            ..eventId = eventId
            ..roomCode = roomCode
            ..stateVersion = stateVersion
            ..eventType = eventType
            ..playerId = playerId
            ..payload = payload
            ..timestamp = DateTime.now()
            ..isPending = isPending
            ..isApplied = false;

      await instance.gameEvents.put(event);
    } catch (e) {}
  }

  static Future<List<isar_models.GameEvent>> getUnappliedEvents(
    String roomCode,
  ) async {
    try {
      return await instance.gameEvents
          .filter()
          .roomCodeEqualTo(roomCode)
          .isAppliedEqualTo(false)
          .sortByStateVersion()
          .thenByTimestamp()
          .findAll();
    } catch (e) {
      return [];
    }
  }

  static Future<void> markEventApplied(String eventId) async {
    try {
      final event =
          await instance.gameEvents
              .filter()
              .eventIdEqualTo(eventId)
              .findFirst();
      if (event != null) {
        event.isApplied = true;
        await instance.gameEvents.put(event);
      }
    } catch (e) {}
  }

  static Future<void> clearPendingEvents(String roomCode) async {
    try {
      await instance.gameEvents
          .filter()
          .roomCodeEqualTo(roomCode)
          .isPendingEqualTo(true)
          .deleteAll();
    } catch (e) {}
  }

  static Future<void> clearRoomData(String roomCode) async {
    try {
      await instance.writeTxn(() async {
        await instance.gameStateSnapshots
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
        await instance.discardPileCards
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
        await instance.playerSnapshots
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
        await instance.playerHands
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
        await instance.gameEvents
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
        await instance.syncMetadatas
            .filter()
            .roomCodeEqualTo(roomCode)
            .deleteAll();
      });
    } catch (e) {}
  }

  static Future<void> markNeedsFullSync(String roomCode) async {
    try {
      final metadata =
          await instance.syncMetadatas
              .filter()
              .roomCodeEqualTo(roomCode)
              .findFirst();

      if (metadata != null) {
        metadata.needsFullSync = true;
        await instance.syncMetadatas.put(metadata);
      } else {
        final newMeta =
            isar_models.SyncMetadata()
              ..roomCode = roomCode
              ..lastAppliedStateVersion = 0
              ..lastSyncAt = DateTime.now()
              ..needsFullSync = true;
        await instance.syncMetadatas.put(newMeta);
      }
    } catch (e) {}
  }
}

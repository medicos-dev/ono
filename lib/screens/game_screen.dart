import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/room_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/uno_card_widget.dart';
import '../widgets/wild_card_animation.dart';
import '../widgets/uno_call_overlay.dart';
import '../widgets/discard_pile_history_overlay.dart';
import '../widgets/card_fly_animation.dart';
import '../widgets/winner_overlay.dart';
import '../widgets/mic_toggle_widget.dart';
import '../widgets/app_toast.dart';
import '../models/card.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import '../services/isar_service.dart';
import 'home_screen.dart';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final ScrollController _handScrollController = ScrollController();
  bool _showWildColorPicker = false;
  UnoCard? _pendingWildCard;
  String? _lastProcessedAnimationId;
  String? _lastWinnerShown;
  final Map<String, GlobalKey> _playerAvatarKeys = {};
  final GlobalKey _discardPileKey = GlobalKey();
  bool _showWinnerOverlay = false;
  int _lastRenderedVersion = 0;
  String? _pendingCardFlyId;
  bool _cardFlyCheckInProgress = false;
  final Set<String> _unoKeysHandled = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRoomStatus();
      _enableWakeLock();
    });
  }

  Future<void> _enableWakeLock() async {
    try {
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      if (roomProvider.isPlaying) {
        await WakelockPlus.enable();
      }
    } catch (e) {}
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {}
  }

  @override
  void dispose() {
    _disableWakeLock();
    WidgetsBinding.instance.removeObserver(this);
    _handScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      roomProvider.stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      roomProvider.startPolling();
    }
  }

  void _checkRoomStatus() {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);

    if (roomProvider.room?.status == RoomStatus.finished) {
      _handleWinner();
      return;
    }

    if (!roomProvider.isPlaying) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LobbyScreen()),
        );
      }
      return;
    }

    if (roomProvider.room == null || roomProvider.currentPlayer == null) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
      return;
    }
  }

  void _handleWinner() {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    final room = roomProvider.room;
    final gameState = room?.gameState;

    if (room == null || gameState == null) return;
    if (gameState.winnerPlayerId == null) return;
    if (_lastWinnerShown == gameState.winnerPlayerId) return;

    _lastWinnerShown = gameState.winnerPlayerId;
    _disableWakeLock();

    setState(() {
      _showWinnerOverlay = true;
    });
  }

  void _showUnoOverlay(String playerName, String animationKey, String roomCode) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => UnoCallOverlay(playerName: playerName),
    ).then((_) {
      IsarService.markAnimationConsumed(roomCode, animationKey);
    });
  }

  void _showDiscardPileHistory(GameState gameState) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) =>
              DiscardPileHistoryOverlay(discardPile: gameState.discardPile),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final room = Provider.of<RoomProvider>(context).room;
    final gameState = room?.gameState;
    final currentVersion = gameState?.stateVersion ?? 0;

    if (room != null && room.status == RoomStatus.playing) {
      _enableWakeLock();
    } else {
      _disableWakeLock();
    }

    if (gameState != null && currentVersion > _lastRenderedVersion) {
      _lastRenderedVersion = currentVersion;

      if (gameState.winnerPlayerId != null && !_showWinnerOverlay) {
        _handleWinner();
      }

      final cardFlyId = gameState.lastPlayedCardAnimationId;
      if (cardFlyId != null &&
          cardFlyId != _lastProcessedAnimationId &&
          _pendingCardFlyId != cardFlyId &&
          !_cardFlyCheckInProgress) {
        _cardFlyCheckInProgress = true;
        IsarService.hasConsumedAnimation(room!.code, cardFlyId).then((consumed) {
          if (!mounted) return;
          setState(() {
            _cardFlyCheckInProgress = false;
            if (consumed) {
              _lastProcessedAnimationId = cardFlyId;
            } else {
              _pendingCardFlyId = cardFlyId;
            }
          });
        });
      }

      final unoCalls = gameState.unoCalled;
      final roomCode = room!.code;
      final stateVersion = gameState.stateVersion;
      for (final entry in unoCalls.entries) {
        if (entry.value != true) continue;
        final playerId = entry.key;
        final animationKey = 'uno_${playerId}_$stateVersion';
        if (_unoKeysHandled.contains(animationKey)) continue;
        _unoKeysHandled.add(animationKey);
        final player = room.players.firstWhere(
          (p) => p.id == playerId,
          orElse: () => room.players.first,
        );
        IsarService.hasConsumedAnimation(roomCode, animationKey).then((consumed) {
          if (!mounted) return;
          if (consumed) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showUnoOverlay(player.name, animationKey, roomCode);
          });
        });
      }
    }
  }

  Future<void> _handlePlayCard(UnoCard card) async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final currentPlayer =
        Provider.of<RoomProvider>(context, listen: false).currentPlayer;

    if (currentPlayer?.isSpectator == true) {
      AppToast.show(
        context,
        'Spectators cannot play cards',
        type: AppToastType.error,
      );
      return;
    }

    if (card.isWild) {
      if (card.type == CardType.wild || card.type == CardType.wildDrawFour) {
        setState(() {
          _showWildColorPicker = true;
          _pendingWildCard = card;
        });
        return;
      }
    }

    try {
      await gameProvider.playCard(
        card,
        chosenColor: gameProvider.pendingColorChoice,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleWildColorChosen(CardColor color) async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);

    if (_pendingWildCard != null) {
      gameProvider.setColorChoice(color);
      await gameProvider.playCard(_pendingWildCard!, chosenColor: color);
    }

    setState(() {
      _showWildColorPicker = false;
      _pendingWildCard = null;
    });
  }

  Future<void> _handleDrawCard() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final currentPlayer =
        Provider.of<RoomProvider>(context, listen: false).currentPlayer;

    if (currentPlayer?.isSpectator == true) {
      AppToast.show(
        context,
        'Spectators cannot draw cards',
        type: AppToastType.error,
      );
      return;
    }

    try {
      await gameProvider.drawCard();
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleCallUno() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final currentPlayer =
        Provider.of<RoomProvider>(context, listen: false).currentPlayer;

    if (currentPlayer?.isSpectator == true) {
      AppToast.show(
        context,
        'Spectators cannot call UNO',
        type: AppToastType.error,
      );
      return;
    }

    try {
      await gameProvider.callUno();
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handlePassTurn() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final currentPlayer =
        Provider.of<RoomProvider>(context, listen: false).currentPlayer;

    if (currentPlayer?.isSpectator == true) {
      AppToast.show(
        context,
        'Spectators cannot pass turn',
        type: AppToastType.error,
      );
      return;
    }

    try {
      await gameProvider.passTurn();
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleExitGame() async {
    await _disableWakeLock();
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    await roomProvider.leaveRoom();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleReturnHome() async {
    await _disableWakeLock();
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    await roomProvider.leaveRoom();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleLeaveRoom() async {
    if (_showWinnerOverlay) {
      await _handleReturnHome();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Game?'),
            content: const Text('Are you sure you want to leave the game?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonRed,
                ),
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _handleReturnHome();
    }
  }

  Offset? _getPlayerAvatarPosition(String playerId) {
    final key = _playerAvatarKeys[playerId];
    if (key?.currentContext == null) return null;
    final RenderBox? renderBox =
        key!.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    return renderBox.localToGlobal(Offset.zero) +
        Offset(renderBox.size.width / 2, renderBox.size.height / 2);
  }

  Offset? _getDiscardPilePosition() {
    if (_discardPileKey.currentContext == null) return null;
    final RenderBox? renderBox =
        _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    return renderBox.localToGlobal(Offset.zero) +
        Offset(renderBox.size.width / 2, renderBox.size.height / 2);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RoomProvider, GameProvider>(
      builder: (context, roomProvider, gameProvider, _) {
        final room = roomProvider.room;
        final currentPlayer = roomProvider.currentPlayer;
        final gameState = room?.gameState;
        final currentVersion = gameState?.stateVersion ?? 0;

        if (room == null || currentPlayer == null) {
          return Scaffold(
            backgroundColor: AppTheme.darkBackground,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F3460),
                    Color(0xFF1A1A2E),
                    Color(0xFF16213E),
                  ],
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                ),
              ),
            ),
          );
        }

        if (gameState == null) {
          return Scaffold(
            backgroundColor: AppTheme.darkBackground,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F3460),
                    Color(0xFF1A1A2E),
                    Color(0xFF16213E),
                  ],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF00E5FF),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading game...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (_showWinnerOverlay && gameState.winnerPlayerId != null) {
          final winner = room.players.firstWhere(
            (p) => p.id == gameState.winnerPlayerId,
            orElse: () => room.players.first,
          );

          return Scaffold(
            body: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A0A0F), Color(0xFF151520)],
                    ),
                  ),
                ),
                WinnerOverlay(
                  winnerName: winner.name,
                  onExitGame: _handleExitGame,
                  onReturnHome: _handleReturnHome,
                ),
              ],
            ),
          );
        }

        _lastRenderedVersion = currentVersion;

        final isMyTurn = gameProvider.isMyTurn && !currentPlayer.isSpectator;
        final topCard = gameState.topDiscardCard;
        final sortedHand = List<UnoCard>.from(currentPlayer.hand)..sort((a, b) {
          if (a.color != b.color) {
            return a.color.index.compareTo(b.color.index);
          }
          if (a.type != b.type) {
            return a.type.index.compareTo(b.type.index);
          }
          return (a.number ?? 0).compareTo(b.number ?? 0);
        });

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: SafeArea(
            bottom: true,
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0F3460),
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildTopBar(
                        context,
                        room,
                        gameState,
                        isMyTurn,
                        currentPlayer,
                      ),
                      _buildOpponentsSection(room, gameState, roomProvider),
                      Expanded(
                        child: _buildGameArea(
                          context,
                          gameState,
                          topCard,
                          isMyTurn,
                          gameProvider,
                          currentPlayer,
                        ),
                      ),
                      if (!currentPlayer.isSpectator) ...[
                        _buildMyHand(
                          sortedHand,
                          gameState,
                          topCard,
                          isMyTurn,
                          gameProvider,
                          currentPlayer,
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'You are spectating this game',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_showWildColorPicker) _buildWildColorPicker(),
                if (_pendingCardFlyId != null &&
                    _pendingCardFlyId == gameState.lastPlayedCardAnimationId)
                  ...(_buildCardFlyAnimation(room, gameState) != null
                      ? [_buildCardFlyAnimation(room, gameState)!]
                      : []),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    Room room,
    GameState gameState,
    bool isMyTurn,
    Player currentPlayer,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _showResignConfirmation(context),
            icon: const Icon(Icons.flag_outlined, color: Colors.white),
            tooltip: 'Resign',
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              room.code,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          if (isMyTurn && !currentPlayer.isSpectator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE94560).withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Text(
                'YOUR TURN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          const Spacer(),
          MicToggleWidget(
            roomCode: room.code,
            displayName: currentPlayer.name,
            size: 48,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _handleLeaveRoom,
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            tooltip: 'Leave Game',
          ),
        ],
      ),
    );
  }

  void _showResignConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.flag, color: Color(0xFFE94560)),
                SizedBox(width: 12),
                Text('Resign Game?', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Are you sure you want to resign? Your cards will be returned to the deck and other players will be notified.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleReturnHome();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                ),
                child: const Text('Resign'),
              ),
            ],
          ),
    );
  }

  Widget _buildOpponentsSection(
    Room room,
    GameState gameState,
    RoomProvider roomProvider,
  ) {
    final opponents =
        room.players
            .where((p) => p.id != roomProvider.currentPlayer?.id)
            .toList();
    final currentPlayerId = gameState.currentTurnPlayerId;

    if (opponents.isEmpty) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: Text(
          'Waiting for other players...',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }

    final playerCount = opponents.length;
    final scaleFactor =
        playerCount > 8
            ? 0.7 - ((playerCount - 8) * 0.05).clamp(0.0, 0.4)
            : 1.0;

    final avatarMargin = 6.0 * scaleFactor;
    final avatarPaddingH = 14.0 * scaleFactor;
    final avatarPaddingV = 10.0 * scaleFactor;
    final nameFontSize = 13.0 * scaleFactor;
    final cardCountFontSize = 12.0 * scaleFactor;
    final iconSize = 14.0 * scaleFactor;
    final unoFontSize = 9.0 * scaleFactor;
    final borderRadius = 14.0 * scaleFactor;
    final sectionHeight = (75.0 * scaleFactor).clamp(50.0, 75.0);

    return Container(
      height: sectionHeight,
      padding: EdgeInsets.symmetric(horizontal: 12 * scaleFactor),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: opponents.length,
        itemBuilder: (context, index) {
          final player = opponents[index];
          final isCurrentTurn = player.id == currentPlayerId;
          final hasUno = gameState.unoCalled[player.id] == true;

          if (!_playerAvatarKeys.containsKey(player.id)) {
            _playerAvatarKeys[player.id] = GlobalKey();
          }

          return Container(
            key: _playerAvatarKeys[player.id],
            margin: EdgeInsets.symmetric(horizontal: avatarMargin),
            padding: EdgeInsets.symmetric(
              horizontal: avatarPaddingH,
              vertical: avatarPaddingV,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient:
                  isCurrentTurn
                      ? const LinearGradient(
                        colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                      )
                      : null,
              color: isCurrentTurn ? null : Colors.white.withOpacity(0.1),
              border: Border.all(
                color:
                    isCurrentTurn
                        ? Colors.transparent
                        : Colors.white.withOpacity(0.2),
                width: 1 * scaleFactor,
              ),
              boxShadow:
                  isCurrentTurn
                      ? [
                        BoxShadow(
                          color: const Color(0xFFE94560).withOpacity(0.4),
                          blurRadius: 10 * scaleFactor,
                          spreadRadius: 1 * scaleFactor,
                        ),
                      ]
                      : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        player.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: nameFontSize,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (hasUno) ...[
                      SizedBox(width: 6 * scaleFactor),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5 * scaleFactor,
                          vertical: 2 * scaleFactor,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDD835),
                          borderRadius: BorderRadius.circular(4 * scaleFactor),
                        ),
                        child: Text(
                          'UNO!',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: unoFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4 * scaleFactor),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.style,
                      color: Colors.white.withOpacity(0.7),
                      size: iconSize,
                    ),
                    SizedBox(width: 4 * scaleFactor),
                    Text(
                      '${player.cardCount}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: cardCountFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameArea(
    BuildContext context,
    GameState gameState,
    UnoCard? topCard,
    bool isMyTurn,
    GameProvider gameProvider,
    Player currentPlayer,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (!currentPlayer.isSpectator && gameProvider.canDrawCard) {
                    _handleDrawCard();
                  }
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 85,
                      height: 125,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                        ),
                        border: Border.all(
                          color:
                              isMyTurn && gameProvider.canDrawCard
                                  ? const Color(0xFFE94560)
                                  : Colors.white24,
                          width: isMyTurn && gameProvider.canDrawCard ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                isMyTurn && gameProvider.canDrawCard
                                    ? const Color(0xFFE94560).withOpacity(0.3)
                                    : Colors.black.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'ONO',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${gameState.drawPile.length}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                            if (isMyTurn && gameProvider.canDrawCard) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE94560),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'DRAW',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (gameState.pendingDrawCount > 0)
                      Positioned(
                        top: -10,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '+${gameState.pendingDrawCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () => _showDiscardPileHistory(gameState),
                child: SizedBox(
                  key: _discardPileKey,
                  child:
                      topCard != null
                          ? topCard.isWild
                              ? WildCardAnimation(
                                child: UnoCardWidget(
                                  card: topCard,
                                  activeColor: gameState.activeColor,
                                  size: UnoCardSize.large,
                                ),
                              )
                              : UnoCardWidget(
                                card: topCard,
                                activeColor: gameState.activeColor,
                                size: UnoCardSize.large,
                              )
                          : Container(
                            width: 140,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 3,
                              ),
                              color: Colors.white.withOpacity(0.05),
                            ),
                            child: const Center(
                              child: Text(
                                'Host\'s\nTurn',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  gameState.direction == 1
                      ? Icons.rotate_right
                      : Icons.rotate_left,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  gameState.direction == 1 ? 'Clockwise' : 'Counter-Clockwise',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (topCard != null &&
              topCard.isWild &&
              gameState.activeColor != CardColor.wild) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: _getColorValue(gameState.activeColor).withOpacity(0.25),
                border: Border.all(
                  color: _getColorValue(gameState.activeColor),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _getColorValue(gameState.activeColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    gameState.activeColor.displayName.toUpperCase(),
                    style: TextStyle(
                      color: _getColorValue(gameState.activeColor),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildCardFlyAnimation(Room room, GameState gameState) {
    final animationId = _pendingCardFlyId ?? gameState.lastPlayedCardAnimationId;
    if (animationId == null) return null;

    final parts = animationId.split('|');
    if (parts.length < 2) return null;

    final playerId = parts[0];
    final cardJson = parts[1];

    UnoCard card;
    try {
      final cardData = jsonDecode(cardJson) as Map<String, dynamic>;
      card = UnoCard.fromJson(cardData);
    } catch (_) {
      return null;
    }

    final startPos = _getPlayerAvatarPosition(playerId);
    final endPos = _getDiscardPilePosition();

    if (startPos == null || endPos == null) return null;

    return CardFlyAnimation(
      card: card,
      startPosition: startPos,
      endPosition: endPos,
      duration: const Duration(milliseconds: 600),
      onComplete: () {
        IsarService.markAnimationConsumed(room.code, animationId);
        if (mounted) {
          setState(() {
            _lastProcessedAnimationId = animationId;
            _pendingCardFlyId = null;
          });
        }
      },
    );
  }

  Color _getColorValue(CardColor color) {
    switch (color) {
      case CardColor.red:
        return const Color(0xFFE53935);
      case CardColor.blue:
        return const Color(0xFF1E88E5);
      case CardColor.green:
        return const Color(0xFF43A047);
      case CardColor.yellow:
        return const Color(0xFFFDD835);
      case CardColor.wild:
        return const Color(0xFF212121);
    }
  }

  Widget _buildMyHand(
    List<UnoCard> hand,
    GameState gameState,
    UnoCard? topCard,
    bool isMyTurn,
    GameProvider gameProvider,
    Player currentPlayer,
  ) {
    if (hand.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasUno =
        currentPlayer.cardCount == 1 &&
        gameState.unoCalled[currentPlayer.id] != true;

    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
        ),
      ),
      child: Column(
        children: [
          if (hasUno)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFDD835), Color(0xFFFFB300)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFDD835).withOpacity(0.6),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎉', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'UNO!',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('🎉', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (gameProvider.canCallUno)
                  GestureDetector(
                    onTap: _handleCallUno,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient:
                            gameProvider.canCallUno
                                ? const LinearGradient(
                                  colors: [
                                    Color(0xFFE53935),
                                    Color(0xFFFF9800),
                                    Color(0xFFFDD835),
                                  ],
                                )
                                : null,
                        color:
                            gameProvider.canCallUno
                                ? null
                                : Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow:
                            gameProvider.canCallUno
                                ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFE53935,
                                    ).withOpacity(0.6),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ]
                                : null,
                      ),
                      child: Text(
                        'UNO!',
                        style: TextStyle(
                          color:
                              gameProvider.canCallUno
                                  ? Colors.white
                                  : Colors.white38,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isMyTurn &&
              !currentPlayer.isSpectator &&
              gameProvider.canPassTurn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ElevatedButton.icon(
                onPressed:
                    gameProvider.isProcessingAction ? null : _handlePassTurn,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('PASS TURN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 150,
            child: ListView.builder(
              controller: _handScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: hand.length,
              itemBuilder: (context, index) {
                final card = hand[index];
                final isSelected = gameProvider.selectedCard == card;
                final isPlayable =
                    isMyTurn && gameProvider.canPlaySpecificCard(card);

                return GestureDetector(
                  onTap:
                      isMyTurn
                          ? () {
                            gameProvider.selectCard(card);
                            if (isPlayable) {
                              _handlePlayCard(card);
                            }
                          }
                          : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Center(
                      child: UnoCardWidget(
                        card: card,
                        isSelected: isSelected,
                        isPlayable: isPlayable,
                        activeColor: gameState.activeColor,
                        size: UnoCardSize.medium,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${currentPlayer.cardCount} cards in hand',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWildColorPicker() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showWildColorPicker = false;
          _pendingWildCard = null;
        });
      },
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choose Color',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildColorButton(CardColor.red),
                        _buildColorButton(CardColor.blue),
                        _buildColorButton(CardColor.green),
                        _buildColorButton(CardColor.yellow),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showWildColorPicker = false;
                          _pendingWildCard = null;
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(CardColor color) {
    return GestureDetector(
      onTap: () => _handleWildColorChosen(color),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: AppTheme.getCardColor(color),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.neonYellow, width: 3),
        ),
      ),
    );
  }
}

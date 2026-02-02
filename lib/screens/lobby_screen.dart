import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../services/webrtc_service.dart';
import '../widgets/app_toast.dart';
import '../theme/app_theme.dart';
import '../models/room.dart';
import 'home_screen.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _isMicPressed = false;
  final Set<String> _shownEventIds = {};
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRoomStatus();
    });
  }

  void _checkRoomStatus() {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    if (roomProvider.isPlaying && !_didNavigate) {
      _didNavigate = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
      return;
    }

    if (roomProvider.room == null || roomProvider.currentPlayer == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return;
    }
  }

  Future<void> _handleStartGame() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);

    if (roomProvider.room!.players.length < 2) {
      AppToast.show(
        context,
        'Need at least 2 players to start',
        type: AppToastType.error,
      );
      return;
    }

    try {
      await roomProvider.startGame();
      // Wait a bit for the game state to be polled
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted &&
          roomProvider.isPlaying &&
          roomProvider.room?.gameState != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()),
        );
      } else if (mounted) {
        // If game state not ready, show error
        AppToast.show(
          context,
          'Game is starting, please wait...',
          type: AppToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: AppToastType.error);
      }
    }
  }

  Future<void> _handleResignHost() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Resign Host?'),
            content: const Text(
              'A random player will be assigned as the new host.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Resign'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await roomProvider.resignHost();
      } catch (e) {
        if (mounted) {
          AppToast.show(context, e.toString(), type: AppToastType.error);
        }
      }
    }
  }

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Room?'),
            content: const Text('Are you sure you want to leave the room?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await roomProvider.leaveRoom();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apple Responsive System
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;

    // Apple UI Constants
    final double headerHeight = h * 0.15;
    final double bottomBarHeight = h * 0.12;

    return Consumer<RoomProvider>(
      builder: (context, roomProvider, _) {
        // Auto-navigate logic (Keep existing)
        if (!_didNavigate &&
            roomProvider.isPlaying &&
            roomProvider.room?.gameState != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_didNavigate) {
              _didNavigate = true;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              );
            }
          });
        }
        if (roomProvider.room == null || roomProvider.currentPlayer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (r) => false,
            );
          });
        }

        final room = roomProvider.room;
        final currentPlayer = roomProvider.currentPlayer;

        if (room != null && room.events != null) {
          for (final e in room.events!) {
            if (e.type == GameEventType.hostChanged && !_shownEventIds.contains(e.eventId)) {
              _shownEventIds.add(e.eventId);
              final newHostName = e.data?['newHostName'] as String?;
              if (mounted) {
                AppToast.show(
                  context,
                  newHostName != null ? '$newHostName is now the host.' : 'Host has been changed.',
                  type: AppToastType.info,
                );
              }
            }
          }
        }

        if (room == null ||
            currentPlayer == null ||
            room.players.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0F),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: const Color(0xFF0A0A0F),
            body: Stack(
            children: [
              // Ambient Background (Consistent with Home)
              Positioned(
                top: -h * 0.1,
                right: -w * 0.2,
                child: Container(
                  width: w * 0.6,
                  height: w * 0.6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.08),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 100,
                        color: const Color(0xFF00E5FF).withOpacity(0.08),
                      ),
                    ],
                  ),
                ),
              ),

              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // iOS Large Title Header
                  SliverAppBar(
                    expandedHeight: headerHeight,
                    backgroundColor: const Color(0xFF0A0A0F).withOpacity(0.9),
                    floating: false,
                    pinned: true,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    leading: const SizedBox.shrink(),
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: EdgeInsets.only(left: w * 0.05, bottom: 16),
                      title: Text(
                        room.code,
                        style: TextStyle(
                          fontFamily: 'SourGummy',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: Colors.white,
                          fontSize: h * 0.035,
                        ), // Scales with device
                      ),
                      background: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: w * 0.05,
                            top: h * 0.05,
                          ),
                          child: Icon(
                            Icons.tag,
                            color: Colors.white.withOpacity(0.1),
                            size: h * 0.1,
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        color: const Color(0xFF1A1A24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        itemBuilder:
                            (context) => [
                              if (roomProvider.isHost)
                                const PopupMenuItem(
                                  value: 'resign',
                                  child: Text(
                                    'Resign Host',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'leave',
                                child: Text(
                                  'Leave Room',
                                  style: TextStyle(color: Color(0xFFFF2D55)),
                                ),
                              ),
                            ],
                        onSelected: (val) {
                          if (val == 'resign') _handleResignHost();
                          if (val == 'leave') _handleLeaveRoom();
                        },
                      ),
                      SizedBox(width: w * 0.04),
                    ],
                  ),

                  // Player List
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.04,
                      h * 0.02,
                      w * 0.04,
                      bottomBarHeight,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final player = room.players[index];
                        final isMe = player.id == currentPlayer.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildGlassPlayerTile(
                            context,
                            player,
                            isMe,
                            w,
                            h,
                          ),
                        );
                      }, childCount: room.players.length),
                    ),
                  ),
                ],
              ),

              // Frosted Glass Bottom Action Bar (above system nav)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        height: bottomBarHeight,
                        padding: EdgeInsets.symmetric(
                        horizontal: w * 0.05,
                        vertical: h * 0.02,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF15151A).withOpacity(0.85),
                        border: Border(
                          top: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Mic Button
                          GestureDetector(
                            onTapDown: (_) async {
                              setState(() => _isMicPressed = true);
                              await WebRTCService().toggleMic(true);
                            },
                            onTapUp: (_) async {
                              setState(() => _isMicPressed = false);
                              await WebRTCService().toggleMic(false);
                            },
                            onTapCancel: () async {
                              setState(() => _isMicPressed = false);
                              await WebRTCService().toggleMic(false);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: bottomBarHeight * 0.6,
                              height: bottomBarHeight * 0.6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    _isMicPressed
                                        ? AppTheme.neonRed
                                        : Colors.white.withOpacity(0.1),
                                boxShadow:
                                    _isMicPressed
                                        ? [
                                          BoxShadow(
                                            color: AppTheme.neonRed.withOpacity(
                                              0.5,
                                            ),
                                            blurRadius: 15,
                                          ),
                                        ]
                                        : [],
                              ),
                              child: Icon(
                                _isMicPressed ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                                size: bottomBarHeight * 0.3,
                              ),
                            ),
                          ),
                          SizedBox(width: w * 0.04),

                          // Action Button
                          Expanded(
                            child:
                                roomProvider.isHost
                                    ? ElevatedButton(
                                      onPressed:
                                          (room.players.length >= 2)
                                              ? _handleStartGame
                                              : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF00E5FF,
                                        ),
                                        foregroundColor: Colors.black,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        disabledBackgroundColor: Colors.white
                                            .withOpacity(0.1),
                                      ),
                                      child: Text(
                                        room.players.length < 2
                                            ? 'WAITING FOR PLAYERS...'
                                            : 'START GAME',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    )
                                    : Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                        ),
                                      ),
                                      child: Text(
                                        'WAITING FOR HOST...',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildGlassPlayerTile(
    BuildContext context,
    dynamic player,
    bool isMe,
    double w,
    double h,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: h * 0.02, horizontal: w * 0.04),
      decoration: BoxDecoration(
        color:
            isMe
                ? const Color(0xFF00E5FF).withOpacity(0.05)
                : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              player.isHost
                  ? AppTheme.neonYellow.withOpacity(0.5)
                  : (isMe
                      ? const Color(0xFF00E5FF).withOpacity(0.3)
                      : Colors.white.withOpacity(0.05)),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: w * 0.12,
            height: w * 0.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  player.isHost
                      ? AppTheme.neonYellow.withOpacity(0.1)
                      : Colors.white.withOpacity(0.05),
              border: Border.all(
                color:
                    player.isHost
                        ? AppTheme.neonYellow
                        : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Center(
              child: Text(
                player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: player.isHost ? AppTheme.neonYellow : Colors.white,
                  fontSize: w * 0.05,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.04),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: h * 0.022,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMe) ...[
                      SizedBox(width: 8),
                      Icon(
                        Icons.person,
                        size: 14,
                        color: const Color(0xFF00E5FF),
                      ),
                    ],
                  ],
                ),
                if (player.isHost)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'HOST',
                      style: TextStyle(
                        color: AppTheme.neonYellow,
                        fontSize: h * 0.012,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Status Indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

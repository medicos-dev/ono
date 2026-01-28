import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../services/voice_service.dart';
import '../widgets/app_toast.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _isMicPressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRoomStatus();
    });
  }

  void _checkRoomStatus() {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    if (roomProvider.isPlaying) {
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
      if (mounted && roomProvider.isPlaying && roomProvider.room?.gameState != null) {
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
        AppToast.show(
          context,
          e.toString(),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleResignHost() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign Host?'),
        content: const Text('A random player will be assigned as the new host.'),
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
          AppToast.show(
            context,
            e.toString(),
            type: AppToastType.error,
          );
        }
      }
    }
  }

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Room?'),
        content: const Text('Are you sure you want to leave the room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await VoiceService.leaveRoom();
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
    final size = MediaQuery.of(context).size;
    final verticalUnit = size.height * 0.02;

    return Consumer<RoomProvider>(
      builder: (context, roomProvider, _) {
        // Auto-navigate to game screen when game starts and gameState is ready
        if (roomProvider.isPlaying && roomProvider.room?.gameState != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
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
              (route) => false,
            );
          });
        }

        final room = roomProvider.room;
        final currentPlayer = roomProvider.currentPlayer;

        if (room == null || currentPlayer == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Room: ${room.code}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                onPressed: _handleLeaveRoom,
                tooltip: 'Leave Room',
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              color: AppTheme.darkBackground,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(size.width * 0.04),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Room Code',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  room.code,
                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                        color: AppTheme.neonBlue,
                                        letterSpacing: 4,
                                      ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.darkSurface,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${room.players.length} player${room.players.length == 1 ? '' : 's'}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.04,
                        vertical: verticalUnit * 0.4,
                      ),
                      itemCount: room.players.length,
                      itemBuilder: (context, index) {
                        final player = room.players[index];
                        final isHost = player.isHost;
                        return Container(
                          margin: EdgeInsets.only(bottom: verticalUnit * 0.6),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isHost ? AppTheme.neonYellow.withOpacity(0.7) : Colors.white.withOpacity(0.06),
                              width: isHost ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isHost ? AppTheme.neonYellow.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                                border: Border.all(
                                  color: isHost ? AppTheme.neonYellow : AppTheme.neonBlue.withOpacity(0.6),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              player.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: isHost
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.neonYellow.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'HOST',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: isHost
                                ? Icon(
                                    Icons.star_rounded,
                                    color: AppTheme.neonYellow,
                                    size: 22,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(size.width * 0.04),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTapDown: (_) async {
                              setState(() => _isMicPressed = true);
                              await VoiceService.startSpeaking();
                            },
                            onTapUp: (_) async {
                              setState(() => _isMicPressed = false);
                              await VoiceService.stopSpeaking();
                            },
                            onTapCancel: () async {
                              setState(() => _isMicPressed = false);
                              await VoiceService.stopSpeaking();
                            },
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: _isMicPressed ? AppTheme.neonRed : AppTheme.neonBlue,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isMicPressed ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (roomProvider.isHost) ...[
                          if (room.players.length >= 2)
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _handleStartGame,
                                child: const Text('START GAME'),
                              ),
                            ),
                          if (room.players.length < 2)
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: null,
                                child: const Text('Need 2+ Players'),
                              ),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _handleResignHost,
                            child: const Text('RESIGN'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

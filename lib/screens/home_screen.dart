import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/room_provider.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../widgets/app_toast.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _playerNameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final savedName = await StorageService.getPlayerName();
    if (savedName != null && mounted) {
      _playerNameController.text = savedName;
    }
  }

  Future<String> _getOrCreatePlayerId() async {
    final existingId = await StorageService.getPlayerId();
    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }
    final newId = const Uuid().v4();
    await StorageService.savePlayerId(newId);
    return newId;
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_roomCodeController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Please enter a room code',
        type: AppToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isCreating = true;
      _isJoining = false;
    });

    try {
      final playerId = await _getOrCreatePlayerId();
      final playerName = _playerNameController.text.trim();
      final roomCode = _roomCodeController.text.trim().toUpperCase();

      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await roomProvider.createRoom(playerName, playerId, roomCode);

      if (!mounted) return;

      // Try to join voice room, but don't fail if it doesn't work
      final joinedVoice = await VoiceService.joinRoom(roomCode, playerId, playerName);
      if (!joinedVoice && mounted) {
        AppToast.show(
          context,
          'Room created, but voice chat unavailable',
          type: AppToastType.info,
        );
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    if (!_formKey.currentState!.validate()) return;
    if (_roomCodeController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Please enter a room code',
        type: AppToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isJoining = true;
      _isCreating = false;
    });

    try {
      final playerId = await _getOrCreatePlayerId();
      final playerName = _playerNameController.text.trim();
      final roomCode = _roomCodeController.text.trim().toUpperCase();

      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await roomProvider.joinRoom(roomCode, playerName, playerId);

      if (!mounted) return;

      // Try to join voice room, but don't fail if it doesn't work
      final joinedVoice = await VoiceService.joinRoom(roomCode, playerId, playerName);
      if (!joinedVoice && mounted) {
        AppToast.show(
          context,
          'Joined room, but voice chat unavailable',
          type: AppToastType.info,
        );
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isJoining = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _playerNameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final verticalUnit = size.height * 0.02;

    return Scaffold(
      body: Container(
        color: const Color(0xFF0A0A0F),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.08,
                vertical: verticalUnit,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(size.width * 0.05),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.03),
                          border: Border.all(
                            color: const Color(0xFF00E5FF).withOpacity(0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Image.asset(
                          'assets/ONO APP LOGO.png',
                          width: 120,
                          height: 120,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.2),
                                border: Border.all(
                                  color: const Color(0xFF00E5FF).withOpacity(0.6),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.casino,
                                size: 60,
                                color: Color(0xFF00E5FF),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: verticalUnit * 1.2),
                      Text(
                        'ONO',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: const Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                              fontSize: 48,
                            ),
                      ),
                      SizedBox(height: verticalUnit * 0.6),
                      Text(
                        'Card Game Arena',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                          letterSpacing: 4,
                        ),
                      ),
                      SizedBox(height: verticalUnit * 2.4),
                      Container(
                        padding: EdgeInsets.all(size.width * 0.06),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _playerNameController,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              decoration: InputDecoration(
                                labelText: 'Player Name',
                                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                hintText: 'Enter your name',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                prefixIcon: Icon(Icons.person_outline, color: Colors.white.withOpacity(0.7)),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your name';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: verticalUnit),
                            TextFormField(
                              controller: _roomCodeController,
                              style: TextStyle(
                                fontSize: 16,
                                letterSpacing: 2,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              decoration: InputDecoration(
                                labelText: 'Room Code',
                                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                hintText: 'e.g. GAME123',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                prefixIcon: Icon(Icons.tag, color: Colors.white.withOpacity(0.7)),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a room code';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: verticalUnit * 1.6),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: (_isLoading && !_isCreating) ? null : _createRoom,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: const Color(0xFF00E5FF).withOpacity(0.4),
                          ),
                          child: (_isLoading && _isCreating)
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.add_circle_outline, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'CREATE ROOM',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: (_isLoading && !_isJoining) ? null : _joinRoom,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: const BorderSide(
                              color: Color(0xFF00E5FF),
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: (_isLoading && _isJoining)
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00E5FF),
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.login, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'JOIN ROOM',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
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
                          const SizedBox(width: 8),
                          Text(
                            'Ready to play',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

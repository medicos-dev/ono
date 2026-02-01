import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/room_provider.dart';
import '../services/storage_service.dart';
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

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LobbyScreen()));
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

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LobbyScreen()));
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
    // Responsive Dimensions (Apple Style System)
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final isTablet = w > 600;

    // Apple UI Constants
    final double cardWidth = isTablet ? w * 0.5 : w * 0.9;
    final double btnHeight = h * 0.07;
    final double borderRadius = 24.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        width: w,
        height: h,
        color: const Color(0xFF0A0A0F), // Theme BG
        child: Stack(
          children: [
            // Ambient Background Blobs (Apple-mesh gradient style)
            Positioned(
              top: -h * 0.2,
              left: -w * 0.2,
              child: Container(
                width: w * 0.8,
                height: w * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: w * 0.4,
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -h * 0.2,
              right: -w * 0.2,
              child: Container(
                width: w * 0.8,
                height: w * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF2D55).withOpacity(0.1),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: w * 0.4,
                      color: const Color(0xFFFF2D55).withOpacity(0.1),
                    ),
                  ],
                ),
              ),
            ),

            // Main Content - Glass Card
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: h * 0.02),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Section
                      Hero(
                        tag: 'logo',
                        child: Container(
                          width: w * 0.25,
                          height: w * 0.25,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/ONO APP LOGO.png',
                              width: w * 0.25,
                              height: w * 0.25,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.casino_outlined,
                                size: w * 0.12,
                                color: const Color(0xFF00E5FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: h * 0.03),
                      Text(
                        'ONO',
                        style: TextStyle(
                          fontFamily: 'SourGummy',
                          fontSize: h * 0.06,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),

                      SizedBox(height: h * 0.05),

                      // Glass Form Input Card
                      Container(
                        width: cardWidth,
                        padding: EdgeInsets.all(w * 0.06),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(borderRadius),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Player Name Input
                              _buildAppleInput(
                                controller: _playerNameController,
                                label: 'Player Name',
                                icon: Icons.person_rounded,
                                size: size,
                              ),
                              SizedBox(height: h * 0.02),
                              // Room Code Input
                              _buildAppleInput(
                                controller: _roomCodeController,
                                label: 'Room Code',
                                icon: Icons.numbers_rounded,
                                size: size,
                                isUpperCase: true,
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: h * 0.04),

                      // Action Buttons
                      SizedBox(
                        width: cardWidth,
                        height: btnHeight,
                        child: ElevatedButton(
                          onPressed:
                              (_isLoading && !_isCreating) ? null : _createRoom,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shadowColor: const Color(
                              0xFF00E5FF,
                            ).withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(borderRadius),
                            ),
                            textStyle: TextStyle(
                              fontSize: h * 0.02,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          child:
                              _isLoading && _isCreating
                                  ? SizedBox(
                                    height: h * 0.03,
                                    width: h * 0.03,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                  : const Text('CREATE ROOM'),
                        ),
                      ),

                      SizedBox(height: h * 0.02),

                      SizedBox(
                        width: cardWidth,
                        height: btnHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(borderRadius),
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: TextButton(
                            onPressed:
                                (_isLoading && !_isJoining) ? null : _joinRoom,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  borderRadius,
                                ),
                              ),
                              splashFactory:
                                  NoSplash.splashFactory, // Apple no-ripple
                            ),
                            child:
                                _isLoading && _isJoining
                                    ? SizedBox(
                                      height: h * 0.03,
                                      width: h * 0.03,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : Text(
                                      'JOIN ROOM',
                                      style: TextStyle(
                                        fontSize: h * 0.02,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: Colors.white,
                                      ),
                                    ),
                          ),
                        ),
                      ),

                      SizedBox(height: h * 0.05),

                      // Footer Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: w * 0.02,
                            height: w * 0.02,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00E5FF),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF00E5FF,
                                  ).withOpacity(0.6),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: w * 0.02),
                          Text(
                            'SERVER ONLINE',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: h * 0.012,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Apple-style Input Field Helper (Refined)
  Widget _buildAppleInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Size size,
    bool isUpperCase = false,
  }) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30), // Pill shape
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        textCapitalization:
            isUpperCase
                ? TextCapitalization.characters
                : TextCapitalization.words,
        style: TextStyle(
          color: Colors.white,
          fontSize: size.height * 0.02,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: size.width * 0.05,
            vertical: size.height * 0.025,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 12, right: 8),
            child: Icon(
              icon,
              color: Colors.white.withOpacity(0.5),
              size: size.height * 0.025,
            ),
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 40),

          fillColor: Colors.black.withOpacity(0.4),
          filled: true,

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(
              color: Color(0xFF00E5FF),
              width: 1.5,
            ), // Blue Glow
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(
              color: Color(0xFFFF2D55),
              width: 1.5,
            ), // Red Error
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Color(0xFFFF2D55), width: 2),
          ),

          hintText: label,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: size.height * 0.02,
            fontWeight: FontWeight.w400,
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFFF2D55),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        validator: (val) => (val == null || val.isEmpty) ? 'Required' : null,
      ),
    );
  }
}

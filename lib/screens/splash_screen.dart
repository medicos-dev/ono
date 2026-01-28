import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../providers/room_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/app_toast.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Animated splash screen with ONO logo and "By Aiks..." text
class SplashScreen extends StatefulWidget {
  final String? apiUrl;

  const SplashScreen({super.key, this.apiUrl});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _bylineController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _bylineOpacity;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState');

    // Warm up GameProvider immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GameProvider>(context, listen: false);
      _requestMicPermission();
    });

    // Logo animation controller
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Text animation controller
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Byline animation controller
    _bylineController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Logo animations
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5)),
    );

    // Text animations
    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    // Byline animation
    _bylineOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _bylineController, curve: Curves.easeIn));

    // Start animations sequence
    _startAnimations();
  }

  Future<void> _requestMicPermission() async {
    print('SplashScreen: Requesting microphone permission');
    final status = await Permission.microphone.status;

    if (status.isGranted) {
      print('SplashScreen: Microphone permission already granted');
      return;
    }

    if (status.isPermanentlyDenied) {
      print('SplashScreen: Microphone permission permanently denied');
      if (mounted) {
        await _showPermissionDeniedDialog();
      }
      return;
    }

    final result = await Permission.microphone.request();

    if (result.isDenied || result.isPermanentlyDenied) {
      print('SplashScreen: Microphone permission denied');
      if (mounted && result.isPermanentlyDenied) {
        await _showPermissionDeniedDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission denied. Voice chat will be disabled.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.darkSurface,
          ),
        );
      }
    } else if (result.isGranted) {
      print('SplashScreen: Microphone permission granted');
    }
  }

  Future<void> _showPermissionDeniedDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.darkSurface,
          title: Text(
            'Microphone Permission Required',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Text(
            'Voice chat requires microphone access. Please enable it in your device settings.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Continue Anyway',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Open Settings'),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      _logoController.forward();
    }

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      _textController.forward();
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _bylineController.forward();
    }

    // Initialize app after animations start
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && !_initialized) {
      _initializeApp();
    }
  }

  Future<void> _initializeApp() async {
    if (_initialized) return;
    _initialized = true;

    print('SplashScreen: Starting initialization');

    try {
      print('SplashScreen: Step 1 - Loading environment');
      try {
        await dotenv.load(fileName: '.env');
        print('SplashScreen: Environment loaded successfully');
        print(
          'SplashScreen: API_URL from .env: ${dotenv.env['API_URL'] ?? 'NOT FOUND'}',
        );
        print(
          'SplashScreen: ZEGO_APP_ID from .env: ${dotenv.env['ZEGO_APP_ID'] ?? 'NOT FOUND'}',
        );
      } catch (e) {
        print('SplashScreen: ERROR - Could not load .env file: $e');
        print(
          'SplashScreen: Make sure .env file exists in root directory and is listed in pubspec.yaml assets',
        );
      }

      print('SplashScreen: WebRTC initialized');

      print('SplashScreen: Step 3 - Initializing API');
      final apiUrl = widget.apiUrl ?? (dotenv.env['API_URL'] ?? '');
      print(
        'SplashScreen: API URL to use: ${apiUrl.isEmpty ? 'EMPTY' : apiUrl}',
      );

      if (apiUrl.isNotEmpty && mounted) {
        try {
          final roomProvider = Provider.of<RoomProvider>(
            context,
            listen: false,
          );
          await roomProvider.initializeApi(apiUrl);
          print('SplashScreen: API initialized successfully with URL: $apiUrl');
        } catch (e) {
          print('SplashScreen: ERROR - API initialization failed: $e');
        }
      } else {
        print('SplashScreen: ERROR - API_URL is empty or not found!');
        print(
          'SplashScreen: Please check your .env file contains: API_URL=https://ono-worker-production.pojofiles.workers.dev',
        );
        if (mounted) {
          AppToast.show(
            context,
            'API URL not configured. Please check .env file.',
            type: AppToastType.error,
          );
        }
      }

      print('SplashScreen: Initialization complete');

      // Wait for animations to complete (total ~2.5 seconds)
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      print('SplashScreen: Error during initialization: $e');
      // Still navigate even if initialization fails
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _bylineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Animated background circles
              ...List.generate(5, (index) => _buildBackgroundCircle(index)),

              // Main content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),

                    // Logo
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _logoOpacity.value,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(40),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFE94560,
                                    ).withOpacity(0.5),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(40),
                                child: Image.asset(
                                  'assets/ONO APP LOGO.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFFE94560),
                                            const Color(
                                              0xFFE94560,
                                            ).withOpacity(0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(40),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'ONO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 40),

                    // App name
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: const Text(
                          'ONO',
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 12,
                            shadows: [
                              Shadow(
                                color: Color(0xFFE94560),
                                blurRadius: 20,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Tagline
                    FadeTransition(
                      opacity: _textOpacity,
                      child: Text(
                        'Multiplayer Card Game',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                          letterSpacing: 4,
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // By Aiks...
                    FadeTransition(
                      opacity: _bylineOpacity,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Text(
                          'By Aiks...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundCircle(int index) {
    final positions = [
      const Alignment(-0.8, -0.6),
      const Alignment(0.9, -0.3),
      const Alignment(-0.5, 0.7),
      const Alignment(0.7, 0.8),
      const Alignment(0.0, -0.9),
    ];

    final sizes = [100.0, 150.0, 80.0, 120.0, 90.0];
    final opacities = [0.1, 0.08, 0.12, 0.06, 0.1];

    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return Align(
          alignment: positions[index],
          child: Opacity(
            opacity: _logoOpacity.value * opacities[index],
            child: Container(
              width: sizes[index] * _logoScale.value,
              height: sizes[index] * _logoScale.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE94560).withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

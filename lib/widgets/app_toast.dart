import 'dart:ui';
import 'package:flutter/material.dart';

enum AppToastType { info, success, error }

class AppToast {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final Color accentColor;
    final IconData icon;
    switch (type) {
      case AppToastType.success:
        accentColor = const Color(
          0xFF00E5FF,
        ); // Neon Blue/Green mix for cyberpunk success
        icon = Icons.check_circle_rounded;
        break;
      case AppToastType.error:
        accentColor = const Color(0xFFFF2D55); // Apple Red
        icon = Icons.error_rounded;
        break;
      case AppToastType.info:
        accentColor = Colors.white;
        icon = Icons.info_rounded;
        break;
    }

    // Ensure only one toast is visible at a time
    _currentEntry?.remove();

    final entry = OverlayEntry(
      builder:
          (context) => _DynamicIslandToast(
            message: message,
            accentColor: accentColor,
            icon: icon,
          ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _DynamicIslandToast extends StatefulWidget {
  final String message;
  final Color accentColor;
  final IconData icon;

  const _DynamicIslandToast({
    required this.message,
    required this.accentColor,
    required this.icon,
  });

  @override
  State<_DynamicIslandToast> createState() => _DynamicIslandToastState();
}

class _DynamicIslandToastState extends State<_DynamicIslandToast>
    with TickerProviderStateMixin {
  AnimationController? _slideController;
  AnimationController? _expandController;
  AnimationController? _fadeController;

  Animation<double>? _slideAnimation;
  Animation<double>? _expandAnimation;
  Animation<double>? _fadeAnimation;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _startAnimation();
  }

  void _initControllers() {
    // Slide down animation (elastic)
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Expand animation (smoother)
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Fade animation (fast)
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -150.0,
      end: 20.0, // Top margin
    ).animate(
      CurvedAnimation(parent: _slideController!, curve: Curves.elasticOut),
    );

    _expandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expandController!, curve: Curves.easeOutQuart),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController!, curve: Curves.easeOut));
  }

  void _startAnimation() async {
    if (_isDisposed || !mounted) return;

    // Phase 1: Symbol slides down
    _slideController?.forward();
    await Future.delayed(const Duration(milliseconds: 300));

    if (_isDisposed || !mounted) return;

    // Phase 2: Expand to show text
    _expandController?.forward();
    await Future.delayed(const Duration(milliseconds: 200));

    if (_isDisposed || !mounted) return;
    _fadeController?.forward();

    // Phase 3: Stay expanded for display duration
    await Future.delayed(const Duration(milliseconds: 2500));

    if (_isDisposed || !mounted) return;

    // Phase 4: Start exit animation
    await _exitAnimation();
  }

  Future<void> _exitAnimation() async {
    if (_isDisposed || !mounted) return;

    // Reverse everything
    _fadeController?.reverse();
    await Future.delayed(const Duration(milliseconds: 100));
    if (_isDisposed || !mounted) return;

    _expandController?.reverse();
    await Future.delayed(const Duration(milliseconds: 200));
    if (_isDisposed || !mounted) return;

    _slideController?.reverse();

    // Remove from overlay
    if (mounted && !_isDisposed) {
      AppToast._currentEntry?.remove();
      AppToast._currentEntry = null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _slideController?.dispose();
    _expandController?.dispose();
    _fadeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slideAnimation == null ||
        _expandAnimation == null ||
        _fadeAnimation == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _slideAnimation!,
                _expandAnimation!,
                _fadeAnimation!,
              ]),
              builder: (context, child) {
                final slideValue = _slideAnimation?.value ?? -150.0;
                final expandValue = _expandAnimation?.value ?? 0.0;
                final fadeValue = _fadeAnimation?.value ?? 0.0;

                return Transform.translate(
                  offset: Offset(0, slideValue),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 360),
                        padding: EdgeInsets.symmetric(
                          horizontal: 16 + (8 * expandValue),
                          vertical: 12 + (4 * expandValue),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F0F12,
                          ).withOpacity(0.75), // Glass Dark
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.accentColor.withOpacity(
                                0.2 * fadeValue,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon - uses accent color
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: widget.accentColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.icon,
                                color: widget.accentColor,
                                size: 20,
                              ),
                            ),

                            // Text - only visible when expanded
                            if (expandValue > 0.3) ...[
                              SizedBox(width: 12 * expandValue),
                              Flexible(
                                child: Opacity(
                                  opacity: expandValue > 0.6 ? fadeValue : 0.0,
                                  child: DefaultTextStyle(
                                    style: const TextStyle(
                                      fontFamily: 'SF Pro Display',
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                      letterSpacing: 0.5,
                                    ),
                                    child: Text(
                                      widget.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
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
  }
}

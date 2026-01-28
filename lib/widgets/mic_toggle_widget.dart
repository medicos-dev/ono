import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';
import 'app_toast.dart';

class MicToggleWidget extends StatefulWidget {
  final String? roomCode;
  final String? displayName;
  final double size;

  const MicToggleWidget({
    super.key,
    required this.roomCode,
    this.displayName,
    this.size = 52,
  });

  @override
  State<MicToggleWidget> createState() => _MicToggleWidgetState();
}

class _MicToggleWidgetState extends State<MicToggleWidget> {
  bool _isMicPressed = false;

  @override
  Widget build(BuildContext context) {
    final hasRoom = widget.roomCode != null && widget.roomCode!.isNotEmpty;
    // We assume readiness if the room is active; WebRTCService handles the internal state
    final enabled = hasRoom;

    Future<void> handlePressDown() async {
      if (!enabled) {
        if (context.mounted) {
          AppToast.show(
            context,
            'Voice chat unavailable (no room code)',
            type: AppToastType.info,
          );
        }
        return;
      }

      setState(() => _isMicPressed = true);
      await WebRTCService().toggleMic(true);
    }

    Future<void> handlePressUp() async {
      if (_isMicPressed) {
        setState(() => _isMicPressed = false);
        await WebRTCService().toggleMic(false);
      }
    }

    return GestureDetector(
      onTapDown: (_) => handlePressDown(),
      onTapUp: (_) => handlePressUp(),
      onTapCancel: () => handlePressUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors:
                _isMicPressed
                    ? const [Color(0xFFE94560), Color(0xFFFF6B6B)]
                    : [Colors.grey.shade800, Colors.grey.shade700],
          ),
          boxShadow: [
            BoxShadow(
              color: (_isMicPressed ? const Color(0xFFE94560) : Colors.black)
                  .withOpacity(0.35),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Icon(
          _isMicPressed ? Icons.mic : Icons.mic_off,
          color: Colors.white,
          size: widget.size * 0.45,
        ),
      ),
    );
  }
}

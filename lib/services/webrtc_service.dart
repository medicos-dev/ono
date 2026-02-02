import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../models/player.dart';

/// Service to handle WebRTC audio chat in a mesh network topology.
/// Replaces Zego Cloud functionality.
class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  final ApiService _apiService = ApiService();

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};

  bool _isInitialized = false;
  String? _currentRoomCode;
  String? _myPlayerId;

  Timer? _signalTimer;
  bool _isPolling = false;
  bool _isMicMuted = true;

  final StreamController<bool> _micStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get micStateStream => _micStateController.stream;
  bool get isMicrophoneOn => !_isMicMuted;

  /// WebRTCService owns its own ApiService instance, so it must be configured
  /// with the same API base URL used by the rest of the app.
  void configureApiBaseUrl(String url) {
    _apiService.initialize(url);
  }

  // Track candidates received before remote description is set
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  static const Map<String, dynamic> _config = {
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  /// Prepare local media stream
  Future<void> initialize() async {
    if (_isInitialized) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    // MNC-grade audio constraints
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'autoGainControl': true,
        'noiseSuppression': true,
        'googEchoCancellation': true,
        'googAutoGainControl': true,
        'googNoiseSuppression': true,
        'googHighpassFilter': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

    // Start muted
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = false;
    });
    _isMicMuted = true;
    _micStateController.add(false);

    _isInitialized = true;
  }

  /// Join a room and start signaling
  Future<void> joinRoom(String roomCode, String playerId) async {
    _currentRoomCode = roomCode;
    _myPlayerId = playerId;

    await initialize();
    _startPolling();
  }

  /// Update mesh connections based on current player list
  void onPlayersChanged(List<Player> players) {
    if (_myPlayerId == null) return;

    final activeIds = players.map((p) => p.id).toSet();
    activeIds.remove(_myPlayerId);

    // 1. Identify new players to connect to
    for (final remoteId in activeIds) {
      if (!_peerConnections.containsKey(remoteId)) {
        // Deterministic collision avoidance:
        // Lexicographically lower ID always sends the offer.
        if (_myPlayerId!.compareTo(remoteId) < 0) {
          _initiateConnection(remoteId);
        }
      }
    }

    // 2. Identify players who left and close connections
    final playersToRemove =
        _peerConnections.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in playersToRemove) {
      _closeConnection(id);
    }
  }

  Future<void> _initiateConnection(String remoteId) async {
    try {
      final pc = await _getOrCreatePeerConnection(remoteId);

      final offer = await pc.createOffer(_config);
      await pc.setLocalDescription(offer);

      await _apiService.sendRTCSignal(
        roomCode: _currentRoomCode!,
        fromPlayerId: _myPlayerId!,
        toPlayerId: remoteId,
        signalType: 'offer',
        signalData: offer.sdp!,
      );
    } catch (e) {}
  }

  Future<RTCPeerConnection> _getOrCreatePeerConnection(String remoteId) async {
    if (_peerConnections.containsKey(remoteId)) {
      return _peerConnections[remoteId]!;
    }

    final pc = await createPeerConnection(_iceServers, _config);
    _peerConnections[remoteId] = pc;

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    // Send candidates to signaling backend
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        try {
          _apiService.sendRTCSignal(
            roomCode: _currentRoomCode!,
            fromPlayerId: _myPlayerId!,
            toPlayerId: remoteId,
            signalType: 'candidate',
            signalData: jsonEncode({
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            }),
          );
        } catch (_) {}
      }
    };

    // Receive remote tracks
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[remoteId] = event.streams[0];
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _closeConnection(remoteId);
      }
    };

    return pc;
  }

  void _closeConnection(String remoteId) {
    _peerConnections[remoteId]?.dispose();
    _peerConnections.remove(remoteId);
    _remoteStreams.remove(remoteId);
    _pendingCandidates.remove(remoteId);
  }

  void _startPolling() {
    _signalTimer?.cancel();
    _isPolling = true;
    _signalTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _pollSignals();
    });
  }

  void stopPolling() {
    _signalTimer?.cancel();
    _signalTimer = null;
    _isPolling = false;
  }

  Future<void> _pollSignals() async {
    if (_myPlayerId == null || !_isPolling) return;

    try {
      final List<dynamic> signalsList = await _apiService.getRTCSignals(
        _myPlayerId!,
      );
      for (final signalObj in signalsList) {
        final signal = signalObj as Map<String, dynamic>;
        await _handleIncomingSignal(signal);
      }
    } catch (e) {
      // Background polling errors suppressed to avoid console noise
    }
  }

  Future<void> _handleIncomingSignal(Map<String, dynamic> signal) async {
    final fromId = signal['from_player_id'] as String;
    final type = signal['signal_type'] as String;
    final data = signal['signal_data'] as String;

    try {
      if (type == 'offer') {
        final pc = await _getOrCreatePeerConnection(fromId);
        await pc.setRemoteDescription(RTCSessionDescription(data, 'offer'));

        final answer = await pc.createAnswer(_config);
        await pc.setLocalDescription(answer);

        await _apiService.sendRTCSignal(
          roomCode: _currentRoomCode!,
          fromPlayerId: _myPlayerId!,
          toPlayerId: fromId,
          signalType: 'answer',
          signalData: answer.sdp!,
        );

        // Process pending candidates
        if (_pendingCandidates.containsKey(fromId)) {
          for (final candidate in _pendingCandidates[fromId]!) {
            await pc.addCandidate(candidate);
          }
          _pendingCandidates.remove(fromId);
        }
      } else if (type == 'answer') {
        final pc = _peerConnections[fromId];
        if (pc != null) {
          await pc.setRemoteDescription(RTCSessionDescription(data, 'answer'));
        }
      } else if (type == 'candidate') {
        final Map<String, dynamic> map = jsonDecode(data);
        final candidate = RTCIceCandidate(
          map['candidate'],
          map['sdpMid'],
          map['sdpMLineIndex'],
        );

        final pc = _peerConnections[fromId];
        if (pc != null && (await pc.getRemoteDescription()) != null) {
          await pc.addCandidate(candidate);
        } else {
          _pendingCandidates.putIfAbsent(fromId, () => []).add(candidate);
        }
      }
    } catch (e) {}
  }

  /// Enable/Disable local microphone (Push-to-Talk)
  Future<void> toggleMic(bool isOn) async {
    if (!_isInitialized) await initialize();

    _isMicMuted = !isOn;

    // Update local stream tracks
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = isOn;
      }
    }

    // Also update tracks on all existing peer connection senders
    for (final pc in _peerConnections.values) {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          sender.track!.enabled = isOn;
        }
      }
    }

    _micStateController.add(isOn);
  }

  /// Reset all connections (e.g., when leaving lobby/game)
  Future<void> leaveRoom() async {
    stopPolling();

    for (var pc in _peerConnections.values) {
      await pc.dispose();
    }
    _peerConnections.clear();
    _remoteStreams.clear();
    _pendingCandidates.clear();

    _currentRoomCode = null;
    _myPlayerId = null;
  }

  /// Full teardown
  Future<void> dispose() async {
    await leaveRoom();
    await _localStream?.dispose();
    _localStream = null;
    _isInitialized = false;
    await _micStateController.close();
  }
}

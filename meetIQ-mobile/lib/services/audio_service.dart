import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'storage_service.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _chunkTimer;
  Timer? _elapsedTimer;
  DateTime? _startTime;
  int _chunkIndex = 0;
  String? _currentMeetingId;
  StorageService? _currentStorage;
  
  // Pause/Resume/Mute state
  bool _isPaused = false;
  bool _isMuted = false;
  void Function(int chunkIndex)? _onChunkStarted;
  
  // Getters for state
  bool get isPaused => _isPaused;
  bool get isMuted => _isMuted;

  Future<bool> hasPermission() async {
    if (kIsWeb) {
      // On web, permission is requested when starting recording
      return true;
    }
    return await _recorder.hasPermission();
  }

  Future<void> startMeeting({
    required String meetingId,
    required Duration chunkDuration,
    required StorageService storage,
    required void Function(int chunkIndex) onChunkStarted,
  }) async {
    // Cancel any existing timers from previous recording
    _chunkTimer?.cancel();
    _elapsedTimer?.cancel();
    
    // Reset state for new recording
    _startTime = DateTime.now();
    _chunkIndex = 0;  // Reset chunk index for new recording
    _currentMeetingId = meetingId;
    _currentStorage = storage;
    _onChunkStarted = onChunkStarted;
    _isPaused = false;
    _isMuted = false;
    
    debugPrint('AudioService: Starting new meeting $meetingId, chunk index reset to $_chunkIndex');
    
    await _startChunk(meetingId, storage, onChunkStarted);
    _chunkTimer?.cancel();
    _chunkTimer = Timer.periodic(chunkDuration, (_) async {
      if (!_isPaused) {
        await _rotateChunk(meetingId, storage, onChunkStarted);
      }
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  Future<void> stopMeeting(String meetingId, StorageService storage) async {
    debugPrint('AudioService: Stopping meeting $meetingId');
    _chunkTimer?.cancel();
    _elapsedTimer?.cancel();
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      debugPrint('AudioService: Final chunk saved: $path');
      // On web, path is a blob URL - store it
      if (kIsWeb && path != null) {
        await storage.addWebChunk(meetingId, path);
      }
    }
    if (_startTime != null) {
      final duration = DateTime.now().difference(_startTime!).inSeconds;
      await storage.setDuration(meetingId, duration);
      debugPrint('AudioService: Meeting $meetingId duration: $duration seconds, total chunks: $_chunkIndex');
    }
    
    // Reset state after stopping
    _currentMeetingId = null;
    _currentStorage = null;
    _onChunkStarted = null;
    _isPaused = false;
    _isMuted = false;
  }

  /// Cancel recording without saving
  Future<void> cancelMeeting(String meetingId, StorageService storage) async {
    debugPrint('AudioService: Cancelling meeting $meetingId');
    _chunkTimer?.cancel();
    _elapsedTimer?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
      // Don't save the chunk
    }
    
    // Delete any saved data for this recording
    await storage.deleteMeeting(meetingId);
    
    // Reset state
    _currentMeetingId = null;
    _currentStorage = null;
    _onChunkStarted = null;
    _isPaused = false;
    _isMuted = false;
  }

  /// Pause recording
  Future<void> pauseRecording() async {
    if (_isPaused) return;
    
    debugPrint('AudioService: Pausing recording');
    _isPaused = true;
    
    // Pause the recorder if it supports it
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    if (!_isPaused) return;
    
    debugPrint('AudioService: Resuming recording');
    _isPaused = false;
    
    // Resume the recorder
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  /// Mute/unmute recording (continues recording but audio is silent)
  void setMuted(bool muted) {
    debugPrint('AudioService: Setting muted to $muted');
    _isMuted = muted;
    // Note: The record package doesn't have a built-in mute feature,
    // but we track the state for UI purposes and silence detection
  }

  /// Get current amplitude for silence detection (returns value between 0 and 1)
  Future<double> getAmplitude() async {
    try {
      final amplitude = await _recorder.getAmplitude();
      // Convert dB to linear scale (0 to 1)
      // Typical values range from -160 (silence) to 0 (max)
      final db = amplitude.current;
      if (db == double.negativeInfinity || db < -60) {
        return 0.0;
      }
      // Normalize: -60dB = 0, 0dB = 1
      return ((db + 60) / 60).clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('AudioService: Error getting amplitude: $e');
      return 0.0;
    }
  }

  Future<void> _rotateChunk(
    String meetingId,
    StorageService storage,
    void Function(int chunkIndex) onChunkStarted,
  ) async {
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      // On web, path is a blob URL - store it
      if (kIsWeb && path != null) {
        await storage.addWebChunk(meetingId, path);
      }
    }
    await _startChunk(meetingId, storage, onChunkStarted);
  }

  Future<void> _startChunk(
    String meetingId,
    StorageService storage,
    void Function(int chunkIndex) onChunkStarted,
  ) async {
    _chunkIndex += 1;
    final dir = await storage.meetingDir(meetingId);
    final isWeb = kIsWeb;
    final extension = isWeb ? 'webm' : 'm4a';
    final encoder = isWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
    final filePath = '${dir.path}/chunk_${_chunkIndex.toString().padLeft(3, '0')}.$extension';
    
    debugPrint('AudioService: Starting chunk $_chunkIndex for meeting $meetingId');
    
    // For web, path is ignored but still required by the API
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        bitRate: 96000,
        sampleRate: 16000,
      ),
      path: filePath,
    );
    
    await storage.incrementChunk(meetingId);
    onChunkStarted(_chunkIndex);
  }
}

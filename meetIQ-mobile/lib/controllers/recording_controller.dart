import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../services/audio_service.dart';
import '../services/storage_service.dart';

class RecordingController extends GetxController {
  final AudioService _audioService = AudioService();
  final StorageService _storageService = StorageService();

  final isRecording = false.obs;
  final isPaused = false.obs;
  final isMuted = false.obs;
  final elapsedSeconds = 0.obs;
  final chunkIndex = 0.obs;
  final recordingId = ''.obs;  // renamed from meetingId for clarity
  final clientName = ''.obs;
  
  // Silence detection
  final currentAmplitude = 0.0.obs;
  final silenceDuration = 0.obs;  // seconds of continuous silence (when NOT muted)
  final muteDuration = 0.obs;     // seconds of being muted
  
  Timer? _timer;
  Timer? _amplitudeTimer;
  static const int silenceThresholdSeconds = 10;
  static const double silenceAmplitudeThreshold = 0.05;  // Below this is considered silence

  Future<bool> startRecording(String client) async {
    if (!await _audioService.hasPermission()) {
      return false;
    }

    // Reset state for new recording
    chunkIndex.value = 0;
    elapsedSeconds.value = 0;
    isPaused.value = false;
    isMuted.value = false;
    silenceDuration.value = 0;
    muteDuration.value = 0;
    currentAmplitude.value = 0.0;

    // Generate unique recording ID
    final id = _storageService.generateRecordingId();
    recordingId.value = id;
    clientName.value = client;
    
    debugPrint('Starting new recording with ID: $id for client: $client');
    
    // Create recording with user-specific storage path
    await _storageService.createMeeting(recordingId: id, clientName: client);

    try {
      await _audioService.startMeeting(
        meetingId: id,
        chunkDuration: const Duration(seconds: 5),  // TODO: Change back to minutes: 5 for production
        storage: _storageService,
        onChunkStarted: (index) => chunkIndex.value = index,
      );
      isRecording.value = true;
      elapsedSeconds.value = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isPaused.value) {
          elapsedSeconds.value += 1;
        }
      });
      
      // Start amplitude monitoring for silence detection
      _startAmplitudeMonitoring();
      
      return true;
    } catch (_) {
      isRecording.value = false;
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
    isRecording.value = false;
    isPaused.value = false;
    isMuted.value = false;
    _timer?.cancel();
    _amplitudeTimer?.cancel();
    await _audioService.stopMeeting(recordingId.value, _storageService);
  }

  /// Cancel the recording without saving
  Future<void> cancelRecording() async {
    if (!isRecording.value) return;
    isRecording.value = false;
    isPaused.value = false;
    isMuted.value = false;
    _timer?.cancel();
    _amplitudeTimer?.cancel();
    await _audioService.cancelMeeting(recordingId.value, _storageService);
  }

  /// Pause the recording
  Future<void> pauseRecording() async {
    if (!isRecording.value || isPaused.value) return;
    await _audioService.pauseRecording();
    isPaused.value = true;
    debugPrint('Recording paused');
  }

  /// Resume the recording
  Future<void> resumeRecording() async {
    if (!isRecording.value || !isPaused.value) return;
    await _audioService.resumeRecording();
    isPaused.value = false;
    silenceDuration.value = 0;  // Reset silence counter
    debugPrint('Recording resumed');
  }

  /// Toggle mute state
  void toggleMute() {
    isMuted.value = !isMuted.value;
    _audioService.setMuted(isMuted.value);
    if (isMuted.value) {
      // Reset mute duration when starting to mute
      muteDuration.value = 0;
    } else {
      // Reset silence duration when unmuting
      silenceDuration.value = 0;
    }
    debugPrint('Recording muted: ${isMuted.value}');
  }

  /// Start monitoring amplitude for silence detection
  void _startAmplitudeMonitoring() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isRecording.value || isPaused.value) return;
      
      final amplitude = await _audioService.getAmplitude();
      currentAmplitude.value = amplitude;
      
      // Track mute duration separately from silence duration
      if (isMuted.value) {
        muteDuration.value += 1;
        // Don't track silence when muted
        silenceDuration.value = 0;
      } else {
        muteDuration.value = 0;
        // Track silence duration only when NOT muted
        if (amplitude < silenceAmplitudeThreshold) {
          silenceDuration.value += 1;
        } else {
          silenceDuration.value = 0;
        }
      }
    });
  }

  /// Check if mute warning should be shown (only when muted for 10+ seconds)
  bool get shouldShowMuteWarning {
    return isRecording.value && 
           !isPaused.value && 
           isMuted.value && 
           muteDuration.value >= silenceThresholdSeconds;
  }

  /// Check if silence warning should be shown (only when NOT muted and silence for 10+ seconds)
  bool get shouldShowSilenceWarning {
    return isRecording.value && 
           !isPaused.value && 
           !isMuted.value && 
           silenceDuration.value >= silenceThresholdSeconds;
  }

  /// Reset silence duration (call after user acknowledges the warning)
  void acknowledgeSilenceWarning() {
    silenceDuration.value = 0;
  }

  /// Reset mute duration (call after user acknowledges the warning)
  void acknowledgeMuteWarning() {
    muteDuration.value = 0;
  }
  
  // Getter for backward compatibility
  RxString get meetingId => recordingId;
}

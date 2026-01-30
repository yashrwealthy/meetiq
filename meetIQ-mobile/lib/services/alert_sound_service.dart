import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service for playing alert sounds
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._internal();
  factory AlertSoundService() => _instance;
  AlertSoundService._internal();

  AudioPlayer? _player;
  bool _initialized = false;

  /// Initialize the audio player
  Future<void> init() async {
    if (_initialized) return;
    
    try {
      _player = AudioPlayer();
      // Set a low volume for alerts
      await _player?.setVolume(0.7);
      _initialized = true;
      debugPrint('AlertSoundService: Initialized');
    } catch (e) {
      debugPrint('AlertSoundService: Failed to initialize: $e');
    }
  }

  /// Play an alert/notification sound
  Future<void> playAlert() async {
    try {
      if (!_initialized) {
        await init();
      }
      
      // Use a data URI for a simple beep sound (works on web and mobile)
      // This is a short alert tone encoded as base64 WAV
      const alertDataUri = 'data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleSkAdJHI5qd5Mx0Eqsl8dUQ8LSI2k/Hn6M6RTVQ3bLL3////6b5fQi8rSL799N+QUDoeM/br/++2Wz4cI0T2/P/+sVg/HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8iQvH+//uxVz4fIkLx/v/7sVc+HyJC8f7/+7FXPh8=';
      
      await _player?.stop();
      await _player?.setSourceUrl(alertDataUri);
      await _player?.resume();
      
      debugPrint('AlertSoundService: Playing alert sound');
    } catch (e) {
      debugPrint('AlertSoundService: Failed to play alert: $e');
      // Fallback: try playing a simple tone using ToneGenerator approach
      await _playFallbackTone();
    }
  }

  /// Fallback method to play a tone
  Future<void> _playFallbackTone() async {
    try {
      // Create a new player for fallback
      final fallbackPlayer = AudioPlayer();
      
      // Try using a different approach - play a very short sound
      await fallbackPlayer.setVolume(0.8);
      
      // Use BytesSource with a generated tone
      final bytes = _generateBeepBytes();
      await fallbackPlayer.play(BytesSource(bytes));
      
      // Dispose after playing
      Future.delayed(const Duration(milliseconds: 500), () {
        fallbackPlayer.dispose();
      });
    } catch (e) {
      debugPrint('AlertSoundService: Fallback tone also failed: $e');
    }
  }

  /// Generate a simple beep sound as WAV bytes
  Uint8List _generateBeepBytes() {
    const sampleRate = 44100;
    const frequency = 800; // Hz
    const duration = 0.3; // seconds
    const amplitude = 0.5;
    
    final numSamples = (sampleRate * duration).toInt();
    final samples = List<int>.generate(numSamples, (i) {
      final t = i / sampleRate;
      // Generate a sine wave with fade in/out
      var envelope = 1.0;
      if (i < numSamples * 0.1) {
        envelope = i / (numSamples * 0.1);
      } else if (i > numSamples * 0.9) {
        envelope = (numSamples - i) / (numSamples * 0.1);
      }
      final value = (amplitude * envelope * 127 * 
          (1 + sin(2 * pi * frequency * t))).toInt();
      return value.clamp(0, 255);
    });
    
    // Create WAV file bytes
    final dataSize = numSamples;
    final fileSize = 36 + dataSize;
    
    final bytes = ByteData(44 + dataSize);
    
    // RIFF header
    bytes.setUint8(0, 0x52); // R
    bytes.setUint8(1, 0x49); // I
    bytes.setUint8(2, 0x46); // F
    bytes.setUint8(3, 0x46); // F
    bytes.setUint32(4, fileSize, Endian.little);
    bytes.setUint8(8, 0x57); // W
    bytes.setUint8(9, 0x41); // A
    bytes.setUint8(10, 0x56); // V
    bytes.setUint8(11, 0x45); // E
    
    // fmt chunk
    bytes.setUint8(12, 0x66); // f
    bytes.setUint8(13, 0x6D); // m
    bytes.setUint8(14, 0x74); // t
    bytes.setUint8(15, 0x20); // (space)
    bytes.setUint32(16, 16, Endian.little); // chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate, Endian.little); // byte rate
    bytes.setUint16(32, 1, Endian.little); // block align
    bytes.setUint16(34, 8, Endian.little); // bits per sample
    
    // data chunk
    bytes.setUint8(36, 0x64); // d
    bytes.setUint8(37, 0x61); // a
    bytes.setUint8(38, 0x74); // t
    bytes.setUint8(39, 0x61); // a
    bytes.setUint32(40, dataSize, Endian.little);
    
    // Write samples
    for (var i = 0; i < numSamples; i++) {
      bytes.setUint8(44 + i, samples[i]);
    }
    
    return bytes.buffer.asUint8List();
  }

  /// Dispose the audio player
  void dispose() {
    _player?.dispose();
    _player = null;
    _initialized = false;
  }
}

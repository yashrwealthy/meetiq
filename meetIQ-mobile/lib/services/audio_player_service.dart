import 'package:flutter/foundation.dart';
import 'dart:async';

import 'storage_service.dart';
import 'audio_player_web.dart' if (dart.library.io) 'audio_player_native.dart' as platform;

class AudioPlayerService {
  final StorageService _storage = StorageService();
  bool _isPlaying = false;
  final _playingController = StreamController<bool>.broadcast();
  
  Stream<bool> get playingStream => _playingController.stream;
  bool get isPlaying => _isPlaying;

  Future<void> playMeeting(String meetingId) async {
    final chunks = await _storage.listChunkFiles(meetingId);
    if (chunks.isEmpty) {
      debugPrint('No audio chunks found for meeting $meetingId');
      return;
    }

    _isPlaying = true;
    _playingController.add(true);
    
    // Play the first chunk (or all chunks sequentially)
    final audioUrl = chunks.first;
    debugPrint('Playing audio from: $audioUrl');
    
    await platform.playAudio(audioUrl, onComplete: () {
      _isPlaying = false;
      _playingController.add(false);
    });
  }

  Future<void> stop() async {
    _isPlaying = false;
    _playingController.add(false);
    await platform.stopAudio();
    debugPrint('Audio playback stopped');
  }

  void dispose() {
    stop();
    _playingController.close();
  }
}

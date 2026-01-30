import 'package:flutter/foundation.dart';
import 'dart:async';

import 'storage_service.dart';
import 'audio_player_web.dart' if (dart.library.io) 'audio_player_native.dart' as platform;

class AudioPlayerService {
  final StorageService _storage = StorageService();
  bool _isPlaying = false;
  bool _shouldStop = false;
  final _playingController = StreamController<bool>.broadcast();
  List<String> _currentChunks = [];
  int _currentChunkIndex = 0;
  
  Stream<bool> get playingStream => _playingController.stream;
  bool get isPlaying => _isPlaying;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalChunks => _currentChunks.length;

  Future<void> playMeeting(String meetingId) async {
    final chunks = await _storage.listChunkFiles(meetingId);
    if (chunks.isEmpty) {
      debugPrint('No audio chunks found for meeting $meetingId');
      return;
    }

    _currentChunks = chunks;
    _currentChunkIndex = 0;
    _shouldStop = false;
    _isPlaying = true;
    _playingController.add(true);
    
    debugPrint('Playing ${chunks.length} chunks for meeting $meetingId');
    
    // Play all chunks sequentially
    await _playNextChunk();
  }

  Future<void> _playNextChunk() async {
    if (_shouldStop || _currentChunkIndex >= _currentChunks.length) {
      // All chunks played or stopped
      _isPlaying = false;
      _playingController.add(false);
      debugPrint('Finished playing all chunks');
      return;
    }

    final audioUrl = _currentChunks[_currentChunkIndex];
    debugPrint('Playing chunk ${_currentChunkIndex + 1}/${_currentChunks.length}: $audioUrl');
    
    await platform.playAudio(audioUrl, onComplete: () {
      if (!_shouldStop) {
        _currentChunkIndex++;
        _playNextChunk();
      }
    });
  }

  Future<void> stop() async {
    _shouldStop = true;
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

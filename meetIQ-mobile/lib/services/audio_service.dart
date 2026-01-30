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
    _startTime = DateTime.now();
    _chunkIndex = 0;
    _currentMeetingId = meetingId;
    _currentStorage = storage;
    await _startChunk(meetingId, storage, onChunkStarted);
    _chunkTimer?.cancel();
    _chunkTimer = Timer.periodic(chunkDuration, (_) async {
      await _rotateChunk(meetingId, storage, onChunkStarted);
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  Future<void> stopMeeting(String meetingId, StorageService storage) async {
    _chunkTimer?.cancel();
    _elapsedTimer?.cancel();
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      // On web, path is a blob URL - store it
      if (kIsWeb && path != null) {
        await storage.addWebChunk(meetingId, path);
      }
    }
    if (_startTime != null) {
      final duration = DateTime.now().difference(_startTime!).inSeconds;
      await storage.setDuration(meetingId, duration);
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

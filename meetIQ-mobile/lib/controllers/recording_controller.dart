import 'dart:async';

import 'package:get/get.dart';

import '../services/audio_service.dart';
import '../services/storage_service.dart';

class RecordingController extends GetxController {
  final AudioService _audioService = AudioService();
  final StorageService _storageService = StorageService();

  final isRecording = false.obs;
  final elapsedSeconds = 0.obs;
  final chunkIndex = 0.obs;
  final recordingId = ''.obs;  // renamed from meetingId for clarity
  final clientName = ''.obs;

  Timer? _timer;

  Future<bool> startRecording(String client) async {
    if (!await _audioService.hasPermission()) {
      return false;
    }

    // Generate unique recording ID
    final id = _storageService.generateRecordingId();
    recordingId.value = id;
    clientName.value = client;
    
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
        elapsedSeconds.value += 1;
      });
      return true;
    } catch (_) {
      isRecording.value = false;
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
    isRecording.value = false;
    _timer?.cancel();
    await _audioService.stopMeeting(recordingId.value, _storageService);
  }
  
  // Getter for backward compatibility
  RxString get meetingId => recordingId;
}

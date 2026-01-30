import 'package:get/get.dart';

import '../models/meeting_result.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';

class UploadController extends GetxController {
  final StorageService _storageService = StorageService();
  final NetworkService _networkService = NetworkService();
  final UploadService _uploadService = UploadService(baseUrl: 'http://127.0.0.1:8000');

  final isUploading = false.obs;
  final progress = 0.0.obs;
  final status = ''.obs;
  final lastResult = Rxn<MeetingResult>();

  Future<bool> uploadMeeting(String meetingId) async {
    if (!await _networkService.isOnline) {
      status.value = 'offline';
      await _storageService.updateMeetingStatus(meetingId, 'pending');
      return false;
    }

    isUploading.value = true;
    status.value = 'uploading';
    progress.value = 0;
    await _storageService.updateMeetingStatus(meetingId, 'uploading');

    final chunks = await _storageService.listChunkFiles(meetingId);
    for (var i = 0; i < chunks.length; i++) {
      final filePath = chunks[i];
      final index = i + 1;
      final ok = await _uploadService.uploadChunk(
        meetingId: meetingId,
        chunkIndex: index,
        filePath: filePath,
      );
      if (!ok) {
        status.value = 'failed';
        isUploading.value = false;
        return false;
      }
      await _storageService.incrementUploaded(meetingId);
      progress.value = (i + 1) / chunks.length;
    }

    final result = await _uploadService.finalizeMeeting(meetingId);
    lastResult.value = result;
    await _storageService.saveMeetingResult(meetingId, result);
    status.value = 'completed';
    isUploading.value = false;
    return true;
  }
}

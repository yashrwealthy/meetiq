import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/meeting_result.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';

class UploadController extends GetxController {
  final StorageService _storageService = StorageService();
  final NetworkService _networkService = NetworkService();
  final UploadService _uploadService = UploadService(baseUrl: 'http://192.168.1.87:8000');
  UserService get _userService => Get.find<UserService>();

  final isUploading = false.obs;
  final isProcessing = false.obs;
  final isCheckingStatus = false.obs;
  final progress = 0.0.obs;
  final status = ''.obs;
  final statusMessage = ''.obs;
  final lastResult = Rxn<MeetingResult>();
  
  // Polling control
  bool _shouldStopPolling = false;
  String? _currentPollingMeetingId;

  /// Stop any ongoing polling when user navigates away
  void stopPolling() {
    debugPrint('UploadController: Stopping polling');
    _shouldStopPolling = true;
  }
  
  /// Reset polling state for new operations
  void _resetPollingState() {
    _shouldStopPolling = false;
  }

  Future<bool> uploadMeeting(String meetingId) async {
    _resetPollingState();
    _currentPollingMeetingId = meetingId;
    
    if (!await _networkService.isOnline) {
      status.value = 'offline';
      statusMessage.value = 'No internet connection';
      await _storageService.updateMeetingStatus(meetingId, 'pending');
      return false;
    }

    // Get client ID
    final clientId = await _userService.getCurrentUserId() ?? 'default_user';

    isUploading.value = true;
    isProcessing.value = false;
    status.value = 'uploading';
    statusMessage.value = 'Preparing upload...';
    progress.value = 0;
    await _storageService.updateMeetingStatus(meetingId, 'uploading');

    final chunks = await _storageService.listChunkFiles(meetingId);
    final totalChunks = chunks.length;

    if (totalChunks == 0) {
      status.value = 'failed';
      statusMessage.value = 'No chunks to upload';
      isUploading.value = false;
      return false;
    }

    debugPrint('Starting upload of $totalChunks chunks for meeting $meetingId');

    // Upload all chunks
    for (var i = 0; i < totalChunks; i++) {
      final filePath = chunks[i];
      statusMessage.value = 'Uploading chunk ${i + 1}/$totalChunks...';
      
      final response = await _uploadService.uploadChunk(
        clientId: clientId,
        meetingId: meetingId,
        chunkIndex: i,
        totalChunks: totalChunks,
        filePath: filePath,
      );

      if (response == null) {
        status.value = 'failed';
        statusMessage.value = 'Failed to upload chunk ${i + 1}';
        isUploading.value = false;
        await _storageService.updateMeetingStatus(meetingId, 'failed');
        return false;
      }

      await _storageService.incrementUploaded(meetingId);
      progress.value = (i + 1) / totalChunks * 0.5;  // Upload is 50% of total progress
    }

    // All chunks uploaded, acknowledge and start processing
    statusMessage.value = 'Verifying upload...';
    isProcessing.value = true;

    final ackResponse = await _uploadService.acknowledgeUpload(
      clientId: clientId,
      meetingId: meetingId,
      totalChunks: totalChunks,
    );

    if (ackResponse == null) {
      status.value = 'failed';
      statusMessage.value = 'Failed to verify upload';
      isUploading.value = false;
      isProcessing.value = false;
      return false;
    }

    // Check for missing chunks and re-upload if needed
    if (ackResponse.missingChunks.isNotEmpty) {
      statusMessage.value = 'Re-uploading ${ackResponse.missingChunks.length} missing chunks...';
      
      for (final missingIndex in ackResponse.missingChunks) {
        if (missingIndex < 0 || missingIndex >= totalChunks) continue;
        
        final response = await _uploadService.uploadChunk(
          clientId: clientId,
          meetingId: meetingId,
          chunkIndex: missingIndex,
          totalChunks: totalChunks,
          filePath: chunks[missingIndex],
        );

        if (response == null) {
          status.value = 'failed';
          statusMessage.value = 'Failed to re-upload chunk $missingIndex';
          isUploading.value = false;
          isProcessing.value = false;
          return false;
        }
      }

      // Acknowledge again after re-uploading missing chunks
      final retryAck = await _uploadService.acknowledgeUpload(
        clientId: clientId,
        meetingId: meetingId,
        totalChunks: totalChunks,
      );

      if (retryAck == null || retryAck.missingChunks.isNotEmpty) {
        status.value = 'failed';
        statusMessage.value = 'Upload verification failed';
        isUploading.value = false;
        isProcessing.value = false;
        return false;
      }
    }

    // Get job ID for fetching results
    final jobId = ackResponse.jobId;
    
    // Save job ID to storage for later status checks
    if (jobId != null && jobId.isNotEmpty) {
      await _storageService.saveJobId(meetingId, jobId);
      debugPrint('Saved job ID $jobId for meeting $meetingId');
    }
    
    // Check if we have a job ID to poll
    if (jobId == null || jobId.isEmpty) {
      // No job ID - cannot poll for status
      debugPrint('No job ID available from ack response');
      status.value = 'failed';
      statusMessage.value = 'No job ID received';
      isUploading.value = false;
      isProcessing.value = false;
      return false;
    }

    // Always poll the status API regardless of ack response status
    // Ack response "complete" just means upload is complete, not processing
    debugPrint('Upload acknowledged, ack status: ${ackResponse.status}');
    debugPrint('Starting to poll status API for job $jobId');
    
    // Update status to show upload complete, now processing
    status.value = 'processing';
    statusMessage.value = 'Uploaded. Processing recording...';
    progress.value = 0.6;
    
    // Update storage status to processing
    await _storageService.updateMeetingStatus(meetingId, 'processing');

    // Poll for job completion
    final result = await _pollForCompletion(meetingId, jobId);

    if (result == null) {
      // Check if polling was cancelled (user navigated away)
      if (_shouldStopPolling) {
        debugPrint('Polling was cancelled by user');
        status.value = 'processing';
        statusMessage.value = 'Processing in background...';
        isUploading.value = false;
        isProcessing.value = false;
        return false;
      }
      
      status.value = 'failed';
      statusMessage.value = 'Processing failed or timed out';
      isUploading.value = false;
      isProcessing.value = false;
      await _storageService.updateMeetingStatus(meetingId, 'failed');
      return false;
    }

    // Save result
    lastResult.value = result;
    await _storageService.saveMeetingResult(meetingId, result);
    
    status.value = 'completed';
    statusMessage.value = 'Processing complete!';
    progress.value = 1.0;
    isUploading.value = false;
    isProcessing.value = false;
    
    return true;
  }

  /// Check status for a meeting that was previously uploaded
  /// Used when user returns to a recording that's still processing
  Future<bool> checkMeetingStatus(String meetingId, String jobId) async {
    _resetPollingState();
    _currentPollingMeetingId = meetingId;
    
    if (!await _networkService.isOnline) {
      status.value = 'offline';
      statusMessage.value = 'No internet connection';
      return false;
    }

    isCheckingStatus.value = true;
    isProcessing.value = true;
    status.value = 'checking';
    statusMessage.value = 'Checking processing status...';
    progress.value = 0.5;

    // Poll for job completion
    final result = await _pollForCompletion(meetingId, jobId);

    if (result == null) {
      // Check if polling was cancelled (user navigated away)
      if (_shouldStopPolling) {
        debugPrint('Status check was cancelled by user');
        status.value = 'processing';
        statusMessage.value = 'Processing in background...';
        isCheckingStatus.value = false;
        isProcessing.value = false;
        return false;
      }
      
      status.value = 'failed';
      statusMessage.value = 'Processing failed or timed out';
      isCheckingStatus.value = false;
      isProcessing.value = false;
      await _storageService.updateMeetingStatus(meetingId, 'failed');
      return false;
    }

    // Save result
    lastResult.value = result;
    await _storageService.saveMeetingResult(meetingId, result);
    
    status.value = 'completed';
    statusMessage.value = 'Processing complete!';
    progress.value = 1.0;
    isCheckingStatus.value = false;
    isProcessing.value = false;
    
    return true;
  }

  Future<MeetingResult?> _pollForCompletion(String meetingId, String jobId) async {
    const maxAttempts = 120;  // 6 minutes max (3s * 120)
    const pollInterval = Duration(seconds: 3);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Check if polling should stop (user navigated away)
      if (_shouldStopPolling) {
        debugPrint('Polling stopped by user at attempt ${attempt + 1}');
        return null;
      }
      
      debugPrint('Polling attempt ${attempt + 1}/$maxAttempts for job $jobId');
      
      final jobStatus = await _uploadService.checkJobStatus(jobId);
      
      if (jobStatus == null) {
        debugPrint('Failed to get job status, retrying...');
        await Future.delayed(pollInterval);
        continue;
      }

      debugPrint('Job status: ${jobStatus.status}, has result: ${jobStatus.result != null}');

      // Check for both "completed" and "complete" status variants
      if (jobStatus.status == 'completed' || jobStatus.status == 'complete') {
        debugPrint('Job completed! Stopping polling.');
        // Return the result (may be null but that's ok, status is completed)
        return jobStatus.result ?? MeetingResult(
          isFinancialMeeting: false,
          financialProducts: [],
          clientIntent: null,
          meetingSummary: ['Processing completed but no summary available'],
          actionItems: [],
          followUpDate: null,
          confidenceLevel: 'low',
        );
      } else if (jobStatus.status == 'failed' || jobStatus.error != null) {
        debugPrint('Job failed: ${jobStatus.error}');
        return null;
      }

      // Update progress (60% to 95% during processing)
      progress.value = 0.6 + (attempt / maxAttempts) * 0.35;
      statusMessage.value = 'Processing... (${(attempt + 1) * 3}s)';
      
      await Future.delayed(pollInterval);
    }

    debugPrint('Polling timed out after $maxAttempts attempts');
    return null;
  }
}

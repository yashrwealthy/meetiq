import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/action_item.dart';
import '../models/follow_up.dart';
import '../models/meeting_result.dart';
import 'storage_service_io.dart' if (dart.library.html) 'storage_service_html.dart' as platform;
import 'user_service.dart';

// Cross-platform directory wrapper
class MeetingDirectory {
  final String path;
  MeetingDirectory(this.path);
}

/// Storage structure:
/// meetiq (root)
///   └── {user_id}
///       └── {recording_id}
///           ├── metadata.json
///           └── chunk_001.webm, chunk_002.webm, ...
class StorageService {
  UserService get _userService => Get.find<UserService>();
  
  // In-memory storage (used for web)
  // Key format: "{userId}/{recordingId}"
  static final Map<String, Map<String, dynamic>> _webMetadata = {};
  static final Map<String, List<String>> _webChunks = {};

  /// Get storage key for a recording (userId/recordingId)
  Future<String> _getStorageKey(String recordingId) async {
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    return '$userId/$recordingId';
  }

  /// Get directory for a specific recording
  Future<MeetingDirectory> meetingDir(String recordingId) async {
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    if (kIsWeb) {
      return MeetingDirectory('/meetiq/$userId/$recordingId');
    }
    final path = await platform.getMeetingDirPath(userId, recordingId);
    return MeetingDirectory(path);
  }

  Future<Map<String, dynamic>> loadMetadata(String recordingId) async {
    final key = await _getStorageKey(recordingId);
    if (kIsWeb) {
      return Map<String, dynamic>.from(_webMetadata[key] ?? {});
    }
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    return await platform.loadMetadata(userId, recordingId);
  }

  Future<void> saveMetadata(String recordingId, Map<String, dynamic> data) async {
    final key = await _getStorageKey(recordingId);
    if (kIsWeb) {
      _webMetadata[key] = Map<String, dynamic>.from(data);
      return;
    }
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    await platform.saveMetadata(userId, recordingId, data);
  }

  /// Generate a unique recording ID
  String generateRecordingId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> createMeeting({
    required String recordingId,
    required String clientName,
  }) async {
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    final now = DateTime.now().toIso8601String();
    
    debugPrint('StorageService: Creating meeting $recordingId for user $userId, client: $clientName');
    
    await saveMetadata(recordingId, {
      'recording_id': recordingId,
      'user_id': userId,
      'client_name': clientName,
      'start_time': now,
      'duration': 0,
      'total_chunks': 0,
      'uploaded_chunks': 0,
      'upload_status': 'pending',
      'is_offline': true,
    });
    if (kIsWeb) {
      final key = await _getStorageKey(recordingId);
      _webChunks[key] = [];
      debugPrint('StorageService: Web storage initialized for key: $key');
      debugPrint('StorageService: Total recordings in web storage: ${_webMetadata.length}');
    }
  }

  Future<void> updateMeetingStatus(String recordingId, String status) async {
    final data = await loadMetadata(recordingId);
    data['upload_status'] = status;
    await saveMetadata(recordingId, data);
  }

  Future<void> incrementChunk(String recordingId) async {
    final data = await loadMetadata(recordingId);
    data['total_chunks'] = (data['total_chunks'] as int? ?? 0) + 1;
    await saveMetadata(recordingId, data);
  }

  Future<void> incrementUploaded(String recordingId) async {
    final data = await loadMetadata(recordingId);
    data['uploaded_chunks'] = (data['uploaded_chunks'] as int? ?? 0) + 1;
    await saveMetadata(recordingId, data);
  }

  Future<void> setDuration(String recordingId, int seconds) async {
    final data = await loadMetadata(recordingId);
    data['duration'] = seconds;
    await saveMetadata(recordingId, data);
  }

  Future<void> saveJobId(String recordingId, String jobId) async {
    final data = await loadMetadata(recordingId);
    data['job_id'] = jobId;
    await saveMetadata(recordingId, data);
  }

  Future<String?> getJobId(String recordingId) async {
    final data = await loadMetadata(recordingId);
    return data['job_id'] as String?;
  }

  /// List all recordings for the current user
  Future<List<Map<String, dynamic>>> listMeetingsMetadata() async {
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    
    if (kIsWeb) {
      final prefix = '$userId/';
      debugPrint('StorageService: Listing meetings for user prefix: $prefix');
      debugPrint('StorageService: All keys in web storage: ${_webMetadata.keys.toList()}');
      
      final list = _webMetadata.entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => Map<String, dynamic>.from(e.value))
          .toList();
      list.sort((a, b) => (b['start_time'] ?? '').compareTo(a['start_time'] ?? ''));
      
      debugPrint('StorageService: Found ${list.length} meetings for user $userId');
      for (final meeting in list) {
        debugPrint('StorageService: - Meeting ${meeting['recording_id']}: ${meeting['client_name']}');
      }
      
      return list;
    }
    return await platform.listMeetingsMetadata(userId);
  }

  Future<List<String>> listChunkFiles(String recordingId) async {
    final key = await _getStorageKey(recordingId);
    if (kIsWeb) {
      return _webChunks[key] ?? [];
    }
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    return await platform.listChunkFiles(userId, recordingId);
  }

  // For web: store blob URL
  Future<void> addWebChunk(String recordingId, String blobUrl) async {
    final key = await _getStorageKey(recordingId);
    _webChunks[key] ??= [];
    _webChunks[key]!.add(blobUrl);
  }

  /// Save an external audio file as a recording chunk
  /// Works for both web (bytes) and native (file copy)
  Future<void> saveExternalAudioFile({
    required String recordingId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    int? fileSizeBytes,
  }) async {
    final key = await _getStorageKey(recordingId);
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    
    // Determine file extension
    final extension = fileName.split('.').last.toLowerCase();
    final chunkName = 'chunk_001.$extension';
    
    if (kIsWeb) {
      // For web, create a blob URL from the bytes for playback
      if (fileBytes != null) {
        final mimeType = platform.getMimeType(fileName);
        final blobUrl = platform.createBlobUrl(fileBytes, mimeType);
        _webChunks[key] ??= [];
        _webChunks[key]!.add(blobUrl);
        debugPrint('StorageService: Created blob URL for web playback: $blobUrl');
      }
    } else {
      // For native, copy the file to the recording directory
      if (filePath != null) {
        final dirPath = await platform.getMeetingDirPath(userId, recordingId);
        final destPath = '$dirPath/$chunkName';
        await platform.copyFile(filePath, destPath);
        debugPrint('StorageService: Copied external file to: $destPath');
      } else if (fileBytes != null) {
        // If we have bytes but no path, write bytes to file
        final dirPath = await platform.getMeetingDirPath(userId, recordingId);
        final destPath = '$dirPath/$chunkName';
        await platform.writeBytes(destPath, fileBytes);
        debugPrint('StorageService: Wrote external file bytes to: $destPath');
      }
    }
    
    // Estimate duration from file size (rough approximation)
    // For MP3: ~1 MB per minute at 128kbps
    // For WAV: ~10 MB per minute at CD quality
    int estimatedDuration = 0;
    final sizeBytes = fileSizeBytes ?? fileBytes?.length ?? 0;
    if (sizeBytes > 0) {
      if (extension == 'wav') {
        // WAV: ~10MB per minute
        estimatedDuration = (sizeBytes / (10 * 1024 * 1024) * 60).round();
      } else {
        // MP3/M4A/others: ~1MB per minute
        estimatedDuration = (sizeBytes / (1024 * 1024) * 60).round();
      }
      // Ensure at least 1 second if we have a file
      if (estimatedDuration == 0) estimatedDuration = 1;
    }
    
    // Update metadata
    final data = await loadMetadata(recordingId);
    data['total_chunks'] = 1;
    data['external_file'] = true;
    data['original_filename'] = fileName;
    data['duration'] = estimatedDuration;
    await saveMetadata(recordingId, data);
  }

  /// Delete a meeting and all its data
  Future<void> deleteMeeting(String recordingId) async {
    final key = await _getStorageKey(recordingId);
    debugPrint('StorageService: Deleting meeting $recordingId');
    
    if (kIsWeb) {
      _webMetadata.remove(key);
      _webChunks.remove(key);
      return;
    }
    
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    await platform.deleteMeeting(userId, recordingId);
  }

  Future<void> saveMeetingResult(String recordingId, MeetingResult result) async {
    final data = await loadMetadata(recordingId);
    
    // Core meeting analysis
    data['meeting_summary'] = result.meetingSummary;
    data['action_items'] = result.actionItems
        .map((text) => ActionItem(id: text.hashCode.toString(), text: text).toJson())
        .toList();
    
    // Save follow-ups from API (list of strings)
    data['follow_ups'] = result.followUps
        .map((text) => FollowUp(
              id: text.hashCode.toString(),
              text: text,
              dueDate: result.followUpDate,
            ).toJson())
        .toList();
    
    // New fields from API
    data['is_financial_meeting'] = result.isFinancialMeeting;
    data['financial_products'] = result.financialProducts;
    data['client_intent'] = result.clientIntent;
    data['confidence_level'] = result.confidenceLevel;
    
    // Status updates
    data['upload_status'] = 'completed';
    data['is_offline'] = false;
    data['processed_at'] = DateTime.now().toIso8601String();
    
    await saveMetadata(recordingId, data);
  }
  
  /// Update client intent
  Future<void> updateClientIntent(String recordingId, String clientIntent) async {
    final data = await loadMetadata(recordingId);
    data['client_intent'] = clientIntent;
    await saveMetadata(recordingId, data);
  }
  
  /// Update meeting summary
  Future<void> updateMeetingSummary(String recordingId, List<String> summary) async {
    final data = await loadMetadata(recordingId);
    data['meeting_summary'] = summary;
    await saveMetadata(recordingId, data);
  }
  
  /// Update action items
  Future<void> updateActionItems(String recordingId, List<ActionItem> actionItems) async {
    final data = await loadMetadata(recordingId);
    data['action_items'] = actionItems.map((item) => item.toJson()).toList();
    await saveMetadata(recordingId, data);
  }
  
  /// Update follow-ups
  Future<void> updateFollowUps(String recordingId, List<FollowUp> followUps) async {
    final data = await loadMetadata(recordingId);
    data['follow_ups'] = followUps.map((item) => item.toJson()).toList();
    await saveMetadata(recordingId, data);
  }
}


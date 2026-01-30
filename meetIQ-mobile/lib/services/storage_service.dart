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

  /// List all recordings for the current user
  Future<List<Map<String, dynamic>>> listMeetingsMetadata() async {
    final userId = await _userService.getCurrentUserId() ?? 'default_user';
    
    if (kIsWeb) {
      final prefix = '$userId/';
      final list = _webMetadata.entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => Map<String, dynamic>.from(e.value))
          .toList();
      list.sort((a, b) => (b['start_time'] ?? '').compareTo(a['start_time'] ?? ''));
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

  Future<void> saveMeetingResult(String recordingId, MeetingResult result) async {
    final data = await loadMetadata(recordingId);
    data['meeting_summary'] = result.meetingSummary;
    data['action_items'] = result.actionItems
        .map((text) => ActionItem(id: text.hashCode.toString(), text: text).toJson())
        .toList();
    data['follow_ups'] = result.followUpDate == null
        ? []
        : [
            FollowUp(
              id: result.followUpDate!,
              text: 'Review meeting follow-up',
              dueDate: result.followUpDate,
            ).toJson(),
          ];
    data['upload_status'] = 'completed';
    data['is_offline'] = false;
    await saveMetadata(recordingId, data);
  }
}


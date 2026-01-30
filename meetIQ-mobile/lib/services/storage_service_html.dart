// Web stub - actual implementation is in storage_service.dart using kIsWeb
// These functions are called but the main storage_service.dart handles web via in-memory storage

/// Get recording directory path: meetiq/{userId}/{recordingId}
Future<String> getMeetingDirPath(String userId, String recordingId) async {
  return '/meetiq/$userId/$recordingId';
}

Future<Map<String, dynamic>> loadMetadata(String userId, String recordingId) async {
  return {};
}

Future<void> saveMetadata(String userId, String recordingId, Map<String, dynamic> data) async {}

Future<List<Map<String, dynamic>>> listMeetingsMetadata(String userId) async {
  return [];
}

Future<List<String>> listChunkFiles(String userId, String recordingId) async {
  return [];
}

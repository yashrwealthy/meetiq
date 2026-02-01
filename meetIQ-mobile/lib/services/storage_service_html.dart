// Web stub - actual implementation is in storage_service.dart using kIsWeb
// These functions are called but the main storage_service.dart handles web via in-memory storage

import 'dart:html' as html;
import 'dart:typed_data';

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

/// Delete a meeting and all its data
Future<void> deleteMeeting(String userId, String recordingId) async {
  // Web storage is handled in-memory in storage_service.dart
}

/// Copy a file from source to destination (web stub)
Future<void> copyFile(String sourcePath, String destPath) async {
  // Web storage is handled in-memory in storage_service.dart
}

/// Write bytes to a file (web stub)
Future<void> writeBytes(String destPath, List<int> bytes) async {
  // Web storage is handled in-memory in storage_service.dart
}

/// Create a blob URL from bytes for web playback
String createBlobUrl(Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

/// Get mime type from file extension
String getMimeType(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  switch (ext) {
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'wav':
      return 'audio/wav';
    case 'webm':
      return 'audio/webm';
    case 'ogg':
      return 'audio/ogg';
    case 'aac':
      return 'audio/aac';
    default:
      return 'audio/mpeg';
  }
}

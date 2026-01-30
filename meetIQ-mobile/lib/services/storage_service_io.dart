import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> _rootDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final root = Directory('${dir.path}/meetiq');
  if (!root.existsSync()) {
    root.createSync(recursive: true);
  }
  return root;
}

/// Get user directory: meetiq/{userId}
Future<Directory> _userDir(String userId) async {
  final root = await _rootDir();
  final dir = Directory('${root.path}/$userId');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// Get recording directory: meetiq/{userId}/{recordingId}
Future<String> getMeetingDirPath(String userId, String recordingId) async {
  final userDir = await _userDir(userId);
  final dir = Directory('${userDir.path}/$recordingId');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir.path;
}

Future<Map<String, dynamic>> loadMetadata(String userId, String recordingId) async {
  final dirPath = await getMeetingDirPath(userId, recordingId);
  final file = File('$dirPath/metadata.json');
  if (!file.existsSync()) {
    return {};
  }
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

Future<void> saveMetadata(String userId, String recordingId, Map<String, dynamic> data) async {
  final dirPath = await getMeetingDirPath(userId, recordingId);
  final file = File('$dirPath/metadata.json');
  await file.writeAsString(jsonEncode(data));
}

/// List all recordings for a specific user
Future<List<Map<String, dynamic>>> listMeetingsMetadata(String userId) async {
  final userDir = await _userDir(userId);
  if (!userDir.existsSync()) return [];
  
  final recordingDirs = userDir.listSync().whereType<Directory>().toList();
  final list = <Map<String, dynamic>>[];
  
  for (final dir in recordingDirs) {
    final file = File('${dir.path}/metadata.json');
    if (file.existsSync()) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      list.add(data);
    }
  }
  list.sort((a, b) => (b['start_time'] ?? '').compareTo(a['start_time'] ?? ''));
  return list;
}

Future<List<String>> listChunkFiles(String userId, String recordingId) async {
  final dirPath = await getMeetingDirPath(userId, recordingId);
  final directory = Directory(dirPath);
  if (!directory.existsSync()) return [];
  final files = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('chunk_'))
      .map((f) => f.path)
      .toList();
  files.sort();
  return files;
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/meeting_result.dart';

class UploadService {
  final String baseUrl;

  UploadService({required this.baseUrl});

  /// Upload chunk from file path (mobile) or blob URL (web)
  Future<bool> uploadChunk({
    required String meetingId,
    required int chunkIndex,
    required String filePath,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/$meetingId/chunks');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chunk_index'] = chunkIndex.toString();

      if (kIsWeb) {
        // On web, filePath is a blob URL - fetch the blob and upload
        final response = await http.get(Uri.parse(filePath));
        request.files.add(http.MultipartFile.fromBytes(
          'audio_chunk',
          response.bodyBytes,
          filename: 'chunk_$chunkIndex.webm',
        ));
      } else {
        // On native, filePath is a file system path
        request.files.add(await http.MultipartFile.fromPath('audio_chunk', filePath));
      }

      final response = await request.send();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Upload error: $e');
      return false;
    }
  }

  Future<MeetingResult> finalizeMeeting(String meetingId) async {
    final uri = Uri.parse('$baseUrl/meetings/$meetingId/finalize');
    final response = await http.post(uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return MeetingResult.fromJson(data);
    }
    return MeetingResult(
      isFinancialMeeting: false,
      financialProducts: const [],
      clientIntent: null,
      meetingSummary: const [],
      actionItems: const [],
      followUpDate: null,
      confidenceLevel: 'low',
    );
  }
}

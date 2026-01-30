import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/meeting_result.dart';
import 'upload_service_io.dart' if (dart.library.html) 'upload_service_html.dart' as platform;

/// Response from chunk upload
class ChunkUploadResponse {
  final String clientId;
  final String meetingId;
  final int chunkId;
  final String status;
  final String? jobId;

  ChunkUploadResponse({
    required this.clientId,
    required this.meetingId,
    required this.chunkId,
    required this.status,
    this.jobId,
  });

  factory ChunkUploadResponse.fromJson(Map<String, dynamic> json) {
    return ChunkUploadResponse(
      clientId: json['client_id'] as String? ?? '',
      meetingId: json['meeting_id'] as String? ?? '',
      chunkId: json['chunk_id'] as int? ?? 0,
      status: json['status'] as String? ?? 'unknown',
      jobId: json['job_id'] as String?,
    );
  }
}

/// Response from acknowledgement API
class AckUploadResponse {
  final String clientId;
  final String meetingId;
  final int totalChunks;
  final int receivedChunksCount;
  final List<int> missingChunks;
  final String status;
  final String? jobId;

  AckUploadResponse({
    required this.clientId,
    required this.meetingId,
    required this.totalChunks,
    required this.receivedChunksCount,
    required this.missingChunks,
    required this.status,
    this.jobId,
  });

  factory AckUploadResponse.fromJson(Map<String, dynamic> json) {
    return AckUploadResponse(
      clientId: json['client_id'] as String? ?? '',
      meetingId: json['meeting_id'] as String? ?? '',
      totalChunks: json['total_chunks'] as int? ?? 0,
      receivedChunksCount: json['received_chunks_count'] as int? ?? 0,
      missingChunks: (json['missing_chunks'] as List<dynamic>? ?? []).cast<int>(),
      status: json['status'] as String? ?? 'unknown',
      jobId: json['job_id'] as String?,
    );
  }
}

/// Response from status API
class JobStatusResponse {
  final String jobId;
  final String status;
  final MeetingResult? result;
  final String? error;

  JobStatusResponse({
    required this.jobId,
    required this.status,
    this.result,
    this.error,
  });

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    MeetingResult? result;
    if (json['result'] != null) {
      result = MeetingResult.fromJson(json['result'] as Map<String, dynamic>);
    }
    return JobStatusResponse(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      result: result,
      error: json['error'] as String?,
    );
  }
}

class UploadService {
  final String baseUrl;

  UploadService({required this.baseUrl});

  /// Upload a single chunk to the server
  Future<ChunkUploadResponse?> uploadChunk({
    required String clientId,
    required String meetingId,
    required int chunkIndex,
    required int totalChunks,
    required String filePath,  // blob URL for web, file path for native
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/upload_chunk');
      final request = http.MultipartRequest('POST', uri)
        ..fields['client_id'] = clientId
        ..fields['meeting_id'] = meetingId
        ..fields['chunk_id'] = chunkIndex.toString()
        ..fields['total_chunks'] = totalChunks.toString();

      if (kIsWeb) {
        // On web, filePath is a blob URL - use platform-specific fetch
        debugPrint('Fetching blob from URL: $filePath');
        final Uint8List? bytes = await platform.fetchBlobBytes(filePath);
        if (bytes == null || bytes.isEmpty) {
          debugPrint('Failed to fetch blob bytes');
          return null;
        }
        debugPrint('Got blob bytes: ${bytes.length} bytes');
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'chunk$chunkIndex.webm',
        ));
      } else {
        // On native, filePath is a file system path
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }

      debugPrint('Uploading chunk $chunkIndex/$totalChunks for meeting $meetingId');
      debugPrint('Request URL: $uri');
      debugPrint('Fields: ${request.fields}');
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: $responseBody');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        debugPrint('Chunk upload response: $data');
        return ChunkUploadResponse.fromJson(data);
      } else {
        debugPrint('Chunk upload failed: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Acknowledge upload completion and start processing
  Future<AckUploadResponse?> acknowledgeUpload({
    required String clientId,
    required String meetingId,
    required int totalChunks,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/ack_upload')
          .replace(queryParameters: {
        'client_id': clientId,
        'meeting_id': meetingId,
        'total_chunks': totalChunks.toString(),
      });

      debugPrint('Acknowledging upload: $uri');
      final response = await http.get(uri);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('Ack response: $data');
        return AckUploadResponse.fromJson(data);
      } else {
        debugPrint('Ack failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Ack error: $e');
      return null;
    }
  }

  /// Check job processing status
  Future<JobStatusResponse?> checkJobStatus(String jobId) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/status/$jobId');
      debugPrint('Checking job status: $uri');
      final response = await http.get(uri);
      
      debugPrint('Status API response code: ${response.statusCode}');
      debugPrint('Status API response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('Parsed job status: ${data['status']}, has result: ${data['result'] != null}');
        final jobStatusResponse = JobStatusResponse.fromJson(data);
        debugPrint('JobStatusResponse created - status: ${jobStatusResponse.status}, result: ${jobStatusResponse.result}');
        return jobStatusResponse;
      } else {
        debugPrint('Status check failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Status check error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Poll for job completion with timeout
  Future<MeetingResult?> waitForJobCompletion(String jobId, {int maxAttempts = 60, Duration pollInterval = const Duration(seconds: 3)}) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final status = await checkJobStatus(jobId);
      if (status == null) {
        debugPrint('Failed to get job status, retrying...');
        await Future.delayed(pollInterval);
        continue;
      }

      // Check for both "completed" and "complete" status variants
      if (status.status == 'completed' || status.status == 'complete') {
        debugPrint('Job completed successfully!');
        return status.result;
      } else if (status.status == 'failed' || status.error != null) {
        debugPrint('Job failed: ${status.error}');
        return null;
      }

      // Still processing, wait and retry
      debugPrint('Job still processing (attempt ${attempt + 1}/$maxAttempts)...');
      await Future.delayed(pollInterval);
    }

    debugPrint('Job timed out after $maxAttempts attempts');
    return null;
  }
}

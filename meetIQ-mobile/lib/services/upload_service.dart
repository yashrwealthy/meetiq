import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/client_memory.dart';
import '../models/client_overview.dart';
import '../models/email_draft.dart';
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
  
  // Flag to stop polling when user navigates away
  bool _shouldStopPolling = false;

  UploadService({required this.baseUrl});

  /// Stop any ongoing polling
  void stopPolling() {
    _shouldStopPolling = true;
  }

  /// Reset polling state for new operations
  void resetPolling() {
    _shouldStopPolling = false;
  }

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
          contentType: MediaType('audio', 'webm'),
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
  /// Polls until status is 'complete' or 'failed' (backend may be uploading to S3)
  Future<AckUploadResponse?> acknowledgeUpload({
    required String clientId,
    required String meetingId,
    required int totalChunks,
    int maxAttempts = 60,  // 3 minutes max (3s * 60)
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Check if polling should stop (user navigated away)
      if (_shouldStopPolling) {
        debugPrint('Ack polling stopped by user at attempt ${attempt + 1}');
        return null;
      }

      try {
        final uri = Uri.parse('$baseUrl/meetings/ack')
            .replace(queryParameters: {
          'client_id': clientId,
          'meeting_id': meetingId,
          'total_chunks': totalChunks.toString(),
        });

        debugPrint('Acknowledging upload (attempt ${attempt + 1}/$maxAttempts): $uri');
        final response = await http.get(uri);
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          debugPrint('Ack response: $data');
          final ackResponse = AckUploadResponse.fromJson(data);
          
          // Check if upload to S3 is complete
          final status = ackResponse.status.toLowerCase();
          if (status == 'complete' || status == 'completed') {
            debugPrint('Ack complete - all chunks uploaded to S3');
            return ackResponse;
          } else if (status == 'failed' || status == 'error') {
            debugPrint('Ack failed: $status');
            return ackResponse;  // Return the failed response so caller can handle
          } else if (status == 'incomplete' || status == 'processing' || status == 'uploading') {
            // Still uploading to S3, continue polling
            debugPrint('Ack status: $status - waiting for S3 upload to complete...');
            await Future.delayed(pollInterval);
            continue;
          } else {
            // Unknown status, treat as complete for backwards compatibility
            debugPrint('Ack unknown status: $status - treating as complete');
            return ackResponse;
          }
        } else {
          debugPrint('Ack failed: ${response.statusCode} - ${response.body}');
          // Retry on server errors
          if (response.statusCode >= 500) {
            await Future.delayed(pollInterval);
            continue;
          }
          return null;
        }
      } catch (e) {
        debugPrint('Ack error: $e');
        // Retry on network errors
        await Future.delayed(pollInterval);
        continue;
      }
    }

    debugPrint('Ack polling timed out after $maxAttempts attempts');
    return null;
  }

  /// Check job processing status
  Future<JobStatusResponse?> checkJobStatus(String jobId) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/status')
          .replace(queryParameters: {'job_id': jobId});
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

  /// Fetch client memory/overview data
  Future<ClientMemory?> fetchClientMemory(String clientId) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/memory')
          .replace(queryParameters: {'client_id': clientId});
      debugPrint('Fetching client memory: $uri');
      final response = await http.get(uri);
      
      debugPrint('Client memory response code: ${response.statusCode}');
      debugPrint('Client memory response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ClientMemory.fromJson(data);
      } else if (response.statusCode == 404) {
        // No memory found for client - this is expected for new clients
        debugPrint('No memory found for client $clientId');
        return null;
      } else {
        debugPrint('Client memory fetch failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Client memory fetch error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Fetch client overview/risk assessment data
  Future<ClientOverview?> fetchClientOverview(String clientId) async {
    try {
      // Use the base URL but replace /v2 with empty to get the root URL
      final rootUrl = baseUrl.replaceAll('/v2', '');
      final uri = Uri.parse('http://127.0.01:8000/v2/clients/$clientId/overview');
      debugPrint('Fetching client overview: $uri');
      final response = await http.get(uri);
      
      debugPrint('Client overview response code: ${response.statusCode}');
      debugPrint('Client overview response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ClientOverview.fromJson(data);
      } else if (response.statusCode == 404) {
        // No overview found for client
        debugPrint('No overview found for client $clientId');
        return null;
      } else {
        debugPrint('Client overview fetch failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Client overview fetch error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Generate email draft based on meeting results
  Future<EmailDraft?> generateEmailDraft({
    required String jobId,
    required String clientName,
    String partnerName = 'Wealthy-Partner',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/email/draft');
      debugPrint('Generating email draft: $uri');
      debugPrint('Request body: {job_id: $jobId, client_name: $clientName, partner_name: $partnerName}');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'job_id': jobId,
          'client_name': clientName,
          'partner_name': partnerName,
        }),
      );
      
      debugPrint('Email draft response code: ${response.statusCode}');
      debugPrint('Email draft response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return EmailDraft.fromJson(data);
      } else {
        debugPrint('Email draft generation failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Email draft generation error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Upload an external audio file (from device storage) as a single chunk
  /// Returns the job_id if successful, null otherwise
  Future<String?> uploadExternalFile({
    required String clientId,
    required String meetingId,
    required String filePath,
    required String fileName,
    Uint8List? fileBytes,  // For web: pass bytes directly
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/meetings/upload_chunk');
      final request = http.MultipartRequest('POST', uri)
        ..fields['client_id'] = clientId
        ..fields['meeting_id'] = meetingId
        ..fields['chunk_id'] = '0'
        ..fields['total_chunks'] = '1';

      // Determine content type from extension
      final ext = fileName.toLowerCase().split('.').last;
      String mimeType = 'audio/mpeg';  // default
      if (ext == 'webm') {
        mimeType = 'audio/webm';
      } else if (ext == 'wav') {
        mimeType = 'audio/wav';
      } else if (ext == 'm4a' || ext == 'aac') {
        mimeType = 'audio/aac';
      } else if (ext == 'ogg') {
        mimeType = 'audio/ogg';
      }

      if (kIsWeb && fileBytes != null) {
        // On web, use bytes directly
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ));
      } else {
        // On native, use file path
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: MediaType.parse(mimeType),
        ));
      }

      debugPrint('Uploading external file: $fileName for meeting $meetingId');
      debugPrint('Request URL: $uri');
      debugPrint('Fields: ${request.fields}');

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: $responseBody');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        debugPrint('External upload response: $data');
        
        // Now acknowledge the upload to trigger processing
        final ackResponse = await acknowledgeUpload(
          clientId: clientId,
          meetingId: meetingId,
          totalChunks: 1,
        );
        
        if (ackResponse != null && ackResponse.jobId != null) {
          debugPrint('External file uploaded and processing started. Job ID: ${ackResponse.jobId}');
          return ackResponse.jobId;
        } else {
          debugPrint('External upload ack failed or no job ID returned');
          return null;
        }
      } else {
        debugPrint('External upload failed: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('External upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }
}

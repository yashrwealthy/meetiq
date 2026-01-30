import 'action_item.dart';
import 'follow_up.dart';

class Meeting {
  final String id;
  final String clientName;
  final String date;
  final int duration;
  final int totalChunks;
  final int uploadedChunks;
  final List<String> summary;
  final List<ActionItem> actionItems;
  final List<FollowUp> followUps;
  final String status;
  final bool isOffline;
  
  // New fields from AI processing
  final bool isFinancialMeeting;
  final List<String> financialProducts;
  final String clientIntent;
  final double confidenceLevel;
  
  // Job tracking
  final String? jobId;

  Meeting({
    required this.id,
    required this.clientName,
    required this.date,
    required this.duration,
    required this.totalChunks,
    required this.uploadedChunks,
    required this.summary,
    required this.actionItems,
    required this.followUps,
    required this.status,
    required this.isOffline,
    this.isFinancialMeeting = false,
    this.financialProducts = const [],
    this.clientIntent = '',
    this.confidenceLevel = 0.0,
    this.jobId,
  });

  /// Parse confidence level from string or number
  static double _parseConfidenceLevel(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      // Convert string levels to numeric values
      switch (value.toLowerCase()) {
        case 'high':
          return 0.9;
        case 'medium':
          return 0.6;
        case 'low':
          return 0.3;
        default:
          // Try parsing as number string
          return double.tryParse(value) ?? 0.0;
      }
    }
    return 0.0;
  }

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: (json['recording_id'] ?? json['meeting_id']) as String,
      clientName: json['client_name'] as String? ?? 'Client',
      date: json['start_time'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      totalChunks: json['total_chunks'] as int? ?? 0,
      uploadedChunks: json['uploaded_chunks'] as int? ?? 0,
      summary: (json['meeting_summary'] as List<dynamic>? ?? []).cast<String>(),
      actionItems: (json['action_items'] as List<dynamic>? ?? [])
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      followUps: (json['follow_ups'] as List<dynamic>? ?? [])
          .map((e) => FollowUp.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['upload_status'] as String? ?? 'draft',
      isOffline: json['is_offline'] as bool? ?? true,
      // New fields
      isFinancialMeeting: json['is_financial_meeting'] as bool? ?? false,
      financialProducts: (json['financial_products'] as List<dynamic>? ?? []).cast<String>(),
      clientIntent: json['client_intent'] as String? ?? '',
      confidenceLevel: _parseConfidenceLevel(json['confidence_level']),
      jobId: json['job_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'meeting_id': id,
      'client_name': clientName,
      'start_time': date,
      'duration': duration,
      'total_chunks': totalChunks,
      'uploaded_chunks': uploadedChunks,
      'meeting_summary': summary,
      'action_items': actionItems.map((e) => e.toJson()).toList(),
      'follow_ups': followUps.map((e) => e.toJson()).toList(),
      'upload_status': status,
      'is_offline': isOffline,
      // New fields
      'is_financial_meeting': isFinancialMeeting,
      'financial_products': financialProducts,
      'client_intent': clientIntent,
      'confidence_level': confidenceLevel,
      'job_id': jobId,
    };
  }
}

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
  });

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
    };
  }
}

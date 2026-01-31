/// Model for client overview/risk assessment response from the API
class ClientOverview {
  final String summaryNarrative;
  final String riskAssessment;
  final String pitchPreparation;
  final List<String> discussionTopics;
  final String clientId;
  final String? lastMeetingDate;

  ClientOverview({
    required this.summaryNarrative,
    required this.riskAssessment,
    required this.pitchPreparation,
    required this.discussionTopics,
    required this.clientId,
    this.lastMeetingDate,
  });

  factory ClientOverview.fromJson(Map<String, dynamic> json) {
    return ClientOverview(
      summaryNarrative: json['summary_narrative'] as String? ?? '',
      riskAssessment: json['risk_assessment'] as String? ?? '',
      pitchPreparation: json['pitch_preparation'] as String? ?? '',
      discussionTopics: (json['discussion_topics'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      clientId: json['client_id'] as String? ?? '',
      lastMeetingDate: json['last_meeting_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary_narrative': summaryNarrative,
      'risk_assessment': riskAssessment,
      'pitch_preparation': pitchPreparation,
      'discussion_topics': discussionTopics,
      'client_id': clientId,
      'last_meeting_date': lastMeetingDate,
    };
  }
}

  class MeetingResult {
  final bool isFinancialMeeting;
  final List<String> financialProducts;
  final String? clientIntent;
  final List<String> meetingSummary;
  final List<String> actionItems;
  final String? followUpDate;
  final String confidenceLevel;

  MeetingResult({
    required this.isFinancialMeeting,
    required this.financialProducts,
    required this.clientIntent,
    required this.meetingSummary,
    required this.actionItems,
    required this.followUpDate,
    required this.confidenceLevel,
  });

  factory MeetingResult.fromJson(Map<String, dynamic> json) {
    return MeetingResult(
      isFinancialMeeting: json['is_financial_meeting'] as bool? ?? false,
      financialProducts: (json['financial_products'] as List<dynamic>? ?? []).cast<String>(),
      clientIntent: json['client_intent'] as String?,
      meetingSummary: (json['meeting_summary'] as List<dynamic>? ?? []).cast<String>(),
      actionItems: (json['action_items'] as List<dynamic>? ?? []).cast<String>(),
      followUpDate: json['follow_up_date'] as String?,
      confidenceLevel: json['confidence_level'] as String? ?? 'low',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_financial_meeting': isFinancialMeeting,
      'financial_products': financialProducts,
      'client_intent': clientIntent,
      'meeting_summary': meetingSummary,
      'action_items': actionItems,
      'follow_up_date': followUpDate,
      'confidence_level': confidenceLevel,
    };
  }
}

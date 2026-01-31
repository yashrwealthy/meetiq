/// Model for financial goal
class FinancialGoal {
  final String name;
  final String status;

  FinancialGoal({
    required this.name,
    required this.status,
  });

  factory FinancialGoal.fromJson(Map<String, dynamic> json) {
    return FinancialGoal(
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
    );
  }
}

/// Model for client memory from the API
class ClientMemory {
  final String clientId;
  final Map<String, dynamic> profile;
  final String? clientOverview;
  final String? riskProfile;
  final List<String> preferredProducts;
  final List<String> disfavoredProducts;
  final List<FinancialGoal> activeFinancialGoals;
  final Map<String, int> discussedProducts;
  final List<String> objectionsHistory;
  final String decisionConfidenceTrend;
  final String engagementLevel;
  final List<String> pendingActionItems;
  final String? lastFollowUpDate;
  final String? lastUpdatedFromMeetingId;
  final String memoryConfidence;

  ClientMemory({
    required this.clientId,
    required this.profile,
    this.clientOverview,
    this.riskProfile,
    required this.preferredProducts,
    required this.disfavoredProducts,
    required this.activeFinancialGoals,
    required this.discussedProducts,
    required this.objectionsHistory,
    required this.decisionConfidenceTrend,
    required this.engagementLevel,
    required this.pendingActionItems,
    this.lastFollowUpDate,
    this.lastUpdatedFromMeetingId,
    required this.memoryConfidence,
  });

  factory ClientMemory.fromJson(Map<String, dynamic> json) {
    return ClientMemory(
      clientId: json['client_id'] as String? ?? '',
      profile: json['profile'] as Map<String, dynamic>? ?? {},
      clientOverview: json['client_overview'] as String?,
      riskProfile: json['risk_profile'] as String?,
      preferredProducts: (json['preferred_products'] as List<dynamic>? ?? []).cast<String>(),
      disfavoredProducts: (json['disfavored_products'] as List<dynamic>? ?? []).cast<String>(),
      activeFinancialGoals: (json['active_financial_goals'] as List<dynamic>? ?? [])
          .map((e) => FinancialGoal.fromJson(e as Map<String, dynamic>))
          .toList(),
      discussedProducts: (json['discussed_products'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int? ?? 0)),
      objectionsHistory: (json['objections_history'] as List<dynamic>? ?? []).cast<String>(),
      decisionConfidenceTrend: json['decision_confidence_trend'] as String? ?? 'stable',
      engagementLevel: json['engagement_level'] as String? ?? 'medium',
      pendingActionItems: (json['pending_action_items'] as List<dynamic>? ?? []).cast<String>(),
      lastFollowUpDate: json['last_follow_up_date'] as String?,
      lastUpdatedFromMeetingId: json['last_updated_from_meeting_id'] as String?,
      memoryConfidence: json['memory_confidence'] as String? ?? 'low',
    );
  }

  /// Check if memory has meaningful data
  bool get hasData => pendingActionItems.isNotEmpty || lastUpdatedFromMeetingId != null || (clientOverview != null && clientOverview!.isNotEmpty);
}

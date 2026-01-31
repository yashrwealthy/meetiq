/// Model for email draft response from the API
class EmailDraft {
  final String jobId;
  final String status;
  final String? subject;
  final String? body;
  final List<String> suggestedAttachments;
  final String? tone;
  final String? error;

  EmailDraft({
    required this.jobId,
    required this.status,
    this.subject,
    this.body,
    this.suggestedAttachments = const [],
    this.tone,
    this.error,
  });

  factory EmailDraft.fromJson(Map<String, dynamic> json) {
    return EmailDraft(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      subject: json['subject'] as String?,
      body: json['body'] as String?,
      suggestedAttachments: (json['suggested_attachments'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tone: json['tone'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_id': jobId,
      'status': status,
      'subject': subject,
      'body': body,
      'suggested_attachments': suggestedAttachments,
      'tone': tone,
      'error': error,
    };
  }

  bool get isSuccess => status == 'success' && subject != null && body != null;
}

class FollowUp {
  final String id;
  final String text;
  final String? dueDate;

  FollowUp({
    required this.id,
    required this.text,
    this.dueDate,
  });

  factory FollowUp.fromJson(Map<String, dynamic> json) {
    return FollowUp(
      id: json['id'] as String,
      text: json['text'] as String,
      dueDate: json['dueDate'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'dueDate': dueDate,
    };
  }
}

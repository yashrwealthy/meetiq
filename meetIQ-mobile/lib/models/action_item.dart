class ActionItem {
  final String id;
  final String text;
  final bool completed;

  ActionItem({
    required this.id,
    required this.text,
    this.completed = false,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      id: json['id'] as String,
      text: json['text'] as String,
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
    };
  }

  ActionItem copyWith({bool? completed}) {
    return ActionItem(
      id: id,
      text: text,
      completed: completed ?? this.completed,
    );
  }
}

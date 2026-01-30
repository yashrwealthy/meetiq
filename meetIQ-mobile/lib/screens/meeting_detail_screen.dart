import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/meetings_controller.dart';
import '../utils/calendar_utils.dart';

class MeetingDetailScreen extends StatelessWidget {
  final String meetingId;

  const MeetingDetailScreen({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MeetingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Detail'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recordings'),
        ),
      ),
      body: FutureBuilder(
        future: controller.loadMeetings(),
        builder: (context, snapshot) {
          final meeting = controller.meetings.firstWhereOrNull((m) => m.id == meetingId);
          if (meeting == null) {
            return const Center(child: Text('Meeting not found'));
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meeting.clientName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Date: ${meeting.date}'),
                  const SizedBox(height: 16),
                  const Text('Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...meeting.summary.map((s) => ListTile(leading: const Icon(Icons.check), title: Text(s))),
                  const SizedBox(height: 12),
                  const Text('Action Items', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...meeting.actionItems.map((a) => CheckboxListTile(value: a.completed, onChanged: (_) {}, title: Text(a.text))),
                  const SizedBox(height: 12),
                  if (meeting.followUps.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: Text(meeting.followUps.first.text),
                      subtitle: Text(meeting.followUps.first.dueDate ?? ''),
                      trailing: TextButton(
                        onPressed: () => openCalendar(meeting.followUps.first.dueDate),
                        child: const Text('Add to Calendar'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

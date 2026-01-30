import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/meetings_controller.dart';
import '../models/meeting.dart';
import '../utils/calendar_utils.dart';
import '../widgets/primary_button.dart';

class SummaryScreen extends StatelessWidget {
  final String meetingId;

  const SummaryScreen({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context) {
    final meetingsController = Get.find<MeetingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Summary'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recordings'),
        ),
      ),
      body: FutureBuilder(
        future: meetingsController.loadMeetings(),
        builder: (context, snapshot) {
          final meeting = meetingsController.meetings.firstWhereOrNull((m) => m.id == meetingId);
          if (meeting == null) {
            return const Center(child: Text('No summary available.'));
          }
          return _SummaryContent(meeting: meeting);
        },
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  final Meeting meeting;

  const _SummaryContent({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Financial Products: ${meeting.summary.isEmpty ? '-' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Meeting Summary', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 24),
            PrimaryButton(
              text: 'Save & Done',
              onPressed: () => context.go('/recordings'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              text: 'New Recording',
              onPressed: () => context.go('/record'),
            ),
          ],
        ),
      ),
    );
  }
}

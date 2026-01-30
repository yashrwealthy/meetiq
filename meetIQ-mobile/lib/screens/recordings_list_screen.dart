import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/meetings_controller.dart';

class RecordingsListScreen extends StatelessWidget {
  const RecordingsListScreen({super.key});

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MeetingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Recordings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/client'),
        ),
      ),
      body: FutureBuilder(
        future: controller.loadMeetings(),
        builder: (context, snapshot) {
          return Obx(() {
            if (controller.meetings.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No recordings yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Start a new recording to get started'),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: controller.meetings.length,
              itemBuilder: (context, index) {
                final meeting = controller.meetings[index];
                final isUploaded = meeting.status == 'completed';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isUploaded ? Colors.green.shade100 : Colors.orange.shade100,
                      child: Icon(
                        isUploaded ? Icons.cloud_done : Icons.cloud_off,
                        color: isUploaded ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(
                      meeting.clientName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(meeting.date)),
                        Text(
                          'Duration: ${_formatDuration(meeting.duration)} • ${meeting.totalChunks} chunks',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    onTap: () => context.go('/recording/${meeting.id}'),
                  ),
                );
              },
            );
          });
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/record'),
        icon: const Icon(Icons.mic),
        label: const Text('New Recording'),
      ),
    );
  }
}

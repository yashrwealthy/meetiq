import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/upload_controller.dart';
import '../widgets/primary_button.dart';

class UploadScreen extends StatelessWidget {
  final String meetingId;

  const UploadScreen({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UploadController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Chunks'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recordings'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Obx(() => LinearProgressIndicator(value: controller.progress.value == 0 ? null : controller.progress.value)),
            const SizedBox(height: 16),
            Obx(() => Text('Status: ${controller.status.value.isEmpty ? 'ready' : controller.status.value}')),
            const Spacer(),
            PrimaryButton(
              text: 'Upload Now',
              onPressed: () async {
                final ok = await controller.uploadMeeting(meetingId);
                if (!context.mounted) return;
                if (ok) {
                  context.go('/processing/$meetingId');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upload failed or offline.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

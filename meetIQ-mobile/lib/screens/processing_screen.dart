import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/processing_controller.dart';

class ProcessingScreen extends StatelessWidget {
  final String meetingId;

  const ProcessingScreen({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ProcessingController());
    controller.start();

    const steps = ['Analyzing', 'Extracting', 'Generating', 'Finalizing'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recordings'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meeting Intelligence is being prepared...', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            Obx(() => Column(
                  children: List.generate(steps.length, (index) {
                    final active = controller.currentStep.value >= index;
                    return ListTile(
                      leading: Icon(active ? Icons.check_circle : Icons.circle_outlined),
                      title: Text(steps[index]),
                    );
                  }),
                )),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                controller.stop();
                context.go('/summary/$meetingId');
              },
              child: const Text('View Summary'),
            ),
          ],
        ),
      ),
    );
  }
}

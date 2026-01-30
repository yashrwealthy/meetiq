import 'dart:async';

import 'package:get/get.dart';

class ProcessingController extends GetxController {
  final currentStep = 0.obs;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    currentStep.value = 0;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (currentStep.value < 3) {
        currentStep.value += 1;
      }
    });
  }

  void stop() {
    _timer?.cancel();
  }
}

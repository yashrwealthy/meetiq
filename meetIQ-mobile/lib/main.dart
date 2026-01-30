import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/routes.dart';
import 'app/theme.dart';
import 'controllers/meetings_controller.dart';
import 'controllers/recording_controller.dart';
import 'controllers/upload_controller.dart';
import 'services/user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize UserService first
  final userService = UserService();
  await userService.initialize();
  Get.put(userService);
  
  Get.put(MeetingsController());
  Get.put(RecordingController());
  Get.put(UploadController());
  runApp(const MeetIQApp());
}

class MeetIQApp extends StatelessWidget {
  const MeetIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MeetIQ',
      theme: AppTheme.light,
      routerConfig: createRouter(),
    );
  }
}

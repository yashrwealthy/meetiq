import 'package:get/get.dart';

import '../models/meeting.dart';
import '../services/storage_service.dart';

class MeetingsController extends GetxController {
  final StorageService _storageService = StorageService();
  final meetings = <Meeting>[].obs;

  Future<void> loadMeetings() async {
    final list = await _storageService.listMeetingsMetadata();
    meetings.assignAll(list.map((e) => Meeting.fromJson(e)).toList());
  }
}

import 'package:go_router/go_router.dart';

import '../screens/client_profile_screen.dart';
import '../screens/meeting_detail_screen.dart';
import '../screens/processing_screen.dart';
import '../screens/record_screen.dart';
import '../screens/recording_detail_screen.dart';
import '../screens/recordings_list_screen.dart';
import '../screens/summary_screen.dart';
import '../screens/token_entry_screen.dart';
import '../screens/upload_screen.dart';

GoRouter createRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const TokenEntryScreen(),
      ),
      GoRoute(
        path: '/client',
        builder: (context, state) => const ClientProfileScreen(),
      ),
      GoRoute(
        path: '/record',
        builder: (context, state) => const RecordScreen(),
      ),
      GoRoute(
        path: '/upload/:meetingId',
        builder: (context, state) => UploadScreen(meetingId: state.pathParameters['meetingId']!),
      ),
      GoRoute(
        path: '/processing/:meetingId',
        builder: (context, state) => ProcessingScreen(meetingId: state.pathParameters['meetingId']!),
      ),
      GoRoute(
        path: '/summary/:meetingId',
        builder: (context, state) => SummaryScreen(meetingId: state.pathParameters['meetingId']!),
      ),
      GoRoute(
        path: '/recordings',
        builder: (context, state) => const RecordingsListScreen(),
      ),
      GoRoute(
        path: '/recording/:meetingId',
        builder: (context, state) => RecordingDetailScreen(meetingId: state.pathParameters['meetingId']!),
      ),
      GoRoute(
        path: '/meeting/:meetingId',
        builder: (context, state) => MeetingDetailScreen(meetingId: state.pathParameters['meetingId']!),
      ),
    ],
  );
}

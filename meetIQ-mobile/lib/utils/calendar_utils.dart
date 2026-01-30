import 'package:url_launcher/url_launcher.dart';

Future<void> openCalendar(String? date) async {
  if (date == null || date.isEmpty) return;
  final uri = Uri.parse('https://calendar.google.com/calendar/r/eventedit?dates=${date}T090000/${date}T100000&text=MeetIQ%20Follow-up');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

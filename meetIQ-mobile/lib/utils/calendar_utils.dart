import 'package:url_launcher/url_launcher.dart';

/// Opens Google Calendar with a pre-filled event
/// If date is provided, uses it; otherwise defaults to tomorrow
Future<void> openCalendar(String? date, {String? title}) async {
  // Use provided date or default to tomorrow
  String eventDate;
  if (date != null && date.isNotEmpty) {
    // Assume date is in YYYY-MM-DD format
    eventDate = date.replaceAll('-', '');
  } else {
    // Default to tomorrow
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    eventDate = '${tomorrow.year}${tomorrow.month.toString().padLeft(2, '0')}${tomorrow.day.toString().padLeft(2, '0')}';
  }
  
  // URL encode the title
  final eventTitle = Uri.encodeComponent(title ?? 'MeetIQ Follow-up');
  
  final uri = Uri.parse(
    'https://calendar.google.com/calendar/r/eventedit'
    '?dates=${eventDate}T090000/${eventDate}T100000'
    '&text=$eventTitle'
  );
  
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Opens Google Calendar with follow-up text as title
Future<void> openCalendarWithFollowUp(String followUpText, {String? date}) async {
  await openCalendar(date, title: followUpText);
}

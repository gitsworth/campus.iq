import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
String weekdayName(int w) => weekdayNames[(w - 1) % 7];
String weekdayShort(int w) => weekdayNames[(w - 1) % 7].substring(0, 3);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// "09:00:00" -> minutes since midnight
int minutesOf(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

/// "13:30:00" -> "1:30 PM"
String fmtTime(String t) {
  final m = minutesOf(t);
  final h = m ~/ 60, mm = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String timeOfDayToDb(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

TimeOfDay dbToTimeOfDay(String t) {
  final m = minutesOf(t);
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

String fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
String fmtDateShort(DateTime d) => DateFormat('d MMM').format(d);

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return DateFormat('d MMM').format(d);
}

String sizeStr(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

Color colorFromHex(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,}]+)').firstMatch(s);
  if (m != null) return m.group(1)!.trim();
  return s.replaceFirst('Exception: ', '').replaceFirst('AuthException(message: ', '');
}

void snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

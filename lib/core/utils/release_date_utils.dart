DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isFutureRelease(DateTime? value, {DateTime? now}) {
  if (value == null) return false;
  return calendarDate(value).isAfter(calendarDate(now ?? DateTime.now()));
}

String releaseDateLabel(DateTime value) =>
    '${value.day} ${_months[value.month - 1]} ${value.year}';

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String comingSoonMessage(DateTime? value, {DateTime? now}) {
  if (value == null || !isFutureRelease(value, now: now)) {
    return 'Not released yet';
  }
  return 'Coming ${releaseDateLabel(value)}';
}

/// DB에 저장하는 날짜('YYYY-MM-DD')와 Dart의 DateTime 사이 변환.
///
/// 날짜는 항상 기기 현지 시간 기준의 "날짜"만 다룹니다 (시각은 버림).
library;

/// DateTime → 'YYYY-MM-DD'
String toDbDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 'YYYY-MM-DD' → 현지 시간 자정의 DateTime
DateTime fromDbDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('날짜 형식이 올바르지 않습니다 (YYYY-MM-DD)', value);
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// 시각을 버리고 날짜만 남깁니다.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// [start]부터 [end]까지 며칠인지 (양 끝 포함).
///
/// 서머타임이 있는 지역에서도 틀리지 않도록 UTC 날짜로 계산합니다.
int daysInclusive(DateTime start, DateTime end) {
  final s = DateTime.utc(start.year, start.month, start.day);
  final e = DateTime.utc(end.year, end.month, end.day);
  return e.difference(s).inDays + 1;
}

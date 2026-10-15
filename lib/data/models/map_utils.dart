/// DB에서 읽은 값을 안전하게 변환하는 도우미.
///
/// SQLite는 REAL 컬럼에 정수를 넣으면 int로 돌려줄 때가 있어서
/// `as double`로 바로 변환하면 런타임 에러가 납니다. 항상 num을 거쳐 변환합니다.
library;

double readDouble(Map<String, Object?> map, String key) =>
    (map[key] as num).toDouble();

double? readDoubleOrNull(Map<String, Object?> map, String key) =>
    (map[key] as num?)?.toDouble();

int readInt(Map<String, Object?> map, String key) => (map[key] as num).toInt();

int? readIntOrNull(Map<String, Object?> map, String key) =>
    (map[key] as num?)?.toInt();

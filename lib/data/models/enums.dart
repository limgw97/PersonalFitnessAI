/// DB에 문자열로 저장되는 선택지들.
///
/// 각 enum의 [dbValue]가 실제로 DB에 저장되는 값입니다.
/// 이미 저장된 데이터와 호환되어야 하므로 dbValue는 한 번 정하면 바꾸지 않습니다.
library;

enum Goal {
  fatLoss('fat_loss'),
  muscleGain('muscle_gain'),
  maintenance('maintenance'),
  endurance('endurance'),
  other('other');

  const Goal(this.dbValue);
  final String dbValue;

  static Goal fromDb(String value) => _fromDb(values, value, (e) => e.dbValue);
}

enum Gender {
  male('male'),
  female('female'),
  other('other');

  const Gender(this.dbValue);
  final String dbValue;

  static Gender fromDb(String value) =>
      _fromDb(values, value, (e) => e.dbValue);
}

enum MealType {
  breakfast('breakfast'),
  lunch('lunch'),
  dinner('dinner'),
  snack('snack');

  const MealType(this.dbValue);
  final String dbValue;

  static MealType fromDb(String value) =>
      _fromDb(values, value, (e) => e.dbValue);
}

enum ExerciseType {
  strength('strength'),
  cardio('cardio');

  const ExerciseType(this.dbValue);
  final String dbValue;

  static ExerciseType fromDb(String value) =>
      _fromDb(values, value, (e) => e.dbValue);
}

T _fromDb<T>(List<T> values, String value, String Function(T) dbValueOf) {
  for (final e in values) {
    if (dbValueOf(e) == value) return e;
  }
  throw ArgumentError.value(value, 'value', '알 수 없는 값');
}

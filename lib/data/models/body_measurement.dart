import '../../core/db_date.dart';
import 'map_utils.dart';

/// 하루 한 번의 신체 측정 기록.
class BodyMeasurement {
  const BodyMeasurement({
    this.id,
    required this.date,
    required this.weight,
    this.bodyFat,
    this.skeletalMuscle,
  });

  final int? id;
  final DateTime date;

  /// kg
  final double weight;

  /// % (선택)
  final double? bodyFat;

  /// kg (선택)
  final double? skeletalMuscle;

  factory BodyMeasurement.fromMap(Map<String, Object?> map) => BodyMeasurement(
        id: readIntOrNull(map, 'id'),
        date: fromDbDate(map['date'] as String),
        weight: readDouble(map, 'weight'),
        bodyFat: readDoubleOrNull(map, 'body_fat'),
        skeletalMuscle: readDoubleOrNull(map, 'skeletal_muscle'),
      );

  Map<String, Object?> toMap() => {
        'date': toDbDate(date),
        'weight': weight,
        'body_fat': bodyFat,
        'skeletal_muscle': skeletalMuscle,
      };

  /// 입력값 검증. 문제가 있으면 [ArgumentError]를 던집니다.
  void validate() {
    if (weight <= 0) throw ArgumentError('체중은 0보다 커야 합니다.');
    final fat = bodyFat;
    if (fat != null && (fat < 0 || fat > 100)) {
      throw ArgumentError('체지방률은 0~100% 사이여야 합니다.');
    }
    final muscle = skeletalMuscle;
    if (muscle != null && muscle <= 0) {
      throw ArgumentError('골격근량은 0보다 커야 합니다.');
    }
  }
}

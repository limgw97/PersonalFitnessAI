import 'enums.dart';
import 'map_utils.dart';

/// 앱 사용자 정보 (DB에는 항상 id = 1인 한 행만 존재).
class UserProfile {
  const UserProfile({
    required this.goal,
    required this.gender,
    required this.age,
    required this.height,
    required this.initialWeight,
  });

  final Goal goal;
  final Gender gender;
  final int age;

  /// cm
  final double height;

  /// kg
  final double initialWeight;

  factory UserProfile.fromMap(Map<String, Object?> map) => UserProfile(
        goal: Goal.fromDb(map['goal'] as String),
        gender: Gender.fromDb(map['gender'] as String),
        age: readInt(map, 'age'),
        height: readDouble(map, 'height'),
        initialWeight: readDouble(map, 'initial_weight'),
      );

  /// id와 created_at은 Repository/DB가 관리하므로 포함하지 않습니다.
  Map<String, Object?> toMap() => {
        'goal': goal.dbValue,
        'gender': gender.dbValue,
        'age': age,
        'height': height,
        'initial_weight': initialWeight,
      };

  /// 입력값 검증. 문제가 있으면 [ArgumentError]를 던집니다.
  void validate() {
    if (age <= 0) throw ArgumentError('나이는 0보다 커야 합니다.');
    if (height <= 0) throw ArgumentError('키는 0보다 커야 합니다.');
    if (initialWeight <= 0) throw ArgumentError('체중은 0보다 커야 합니다.');
  }
}

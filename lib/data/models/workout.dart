import '../../core/db_date.dart';
import 'enums.dart';
import 'map_utils.dart';

/// 운동 세션 하나 (예: 10월 11일 저녁 헬스).
///
/// 구조: Workout → WorkoutExercise(종목) → WorkoutSet(세트, 근력 전용)
class Workout {
  const Workout({
    this.id,
    required this.date,
    this.memo,
    this.exercises = const [],
  });

  final int? id;
  final DateTime date;
  final String? memo;

  /// 종목 목록. 저장할 때 리스트 순서대로 order_index가 매겨집니다.
  final List<WorkoutExercise> exercises;

  factory Workout.fromMap(
    Map<String, Object?> map, {
    List<WorkoutExercise> exercises = const [],
  }) =>
      Workout(
        id: readIntOrNull(map, 'id'),
        date: fromDbDate(map['date'] as String),
        memo: map['memo'] as String?,
        exercises: exercises,
      );

  Map<String, Object?> toMap() => {
        'date': toDbDate(date),
        'memo': memo,
      };

  bool get hasStrength =>
      exercises.any((e) => e.type == ExerciseType.strength);

  bool get hasCardio => exercises.any((e) => e.type == ExerciseType.cardio);

  /// 세션 전체 검증. 문제가 있으면 [ArgumentError]를 던집니다.
  void validate() {
    if (exercises.isEmpty) {
      throw ArgumentError('운동 종목을 하나 이상 추가하세요.');
    }
    for (final exercise in exercises) {
      exercise.validate();
    }
  }
}

/// 운동 종목 하나 (예: Chest Press, Treadmill).
///
/// - strength: [sets]에 세트별 무게×횟수, cardio 필드는 모두 null
/// - cardio: [sets]는 비어 있고, 시간/거리 중 하나 이상 입력
class WorkoutExercise {
  const WorkoutExercise({
    this.id,
    required this.name,
    required this.type,
    this.durationMin,
    this.distanceKm,
    this.avgSpeed,
    this.sets = const [],
  });

  /// 근력 종목
  const WorkoutExercise.strength({
    this.id,
    required this.name,
    required this.sets,
  })  : type = ExerciseType.strength,
        durationMin = null,
        distanceKm = null,
        avgSpeed = null;

  /// 유산소 종목
  const WorkoutExercise.cardio({
    this.id,
    required this.name,
    this.durationMin,
    this.distanceKm,
    this.avgSpeed,
  })  : type = ExerciseType.cardio,
        sets = const [];

  final int? id;
  final String name;
  final ExerciseType type;

  /// 분 (cardio 전용)
  final double? durationMin;

  /// km (cardio 전용)
  final double? distanceKm;

  /// km/h (cardio 전용)
  final double? avgSpeed;

  /// 세트 목록 (strength 전용). 저장할 때 리스트 순서대로 set_number가 매겨집니다.
  final List<WorkoutSet> sets;

  factory WorkoutExercise.fromMap(
    Map<String, Object?> map, {
    List<WorkoutSet> sets = const [],
  }) =>
      WorkoutExercise(
        id: readIntOrNull(map, 'id'),
        name: map['exercise_name'] as String,
        type: ExerciseType.fromDb(map['exercise_type'] as String),
        durationMin: readDoubleOrNull(map, 'duration_min'),
        distanceKm: readDoubleOrNull(map, 'distance_km'),
        avgSpeed: readDoubleOrNull(map, 'avg_speed'),
        sets: sets,
      );

  /// workout_id와 order_index는 Repository가 저장할 때 채웁니다.
  Map<String, Object?> toMap() => {
        'exercise_name': name,
        'exercise_type': type.dbValue,
        'duration_min': durationMin,
        'distance_km': distanceKm,
        'avg_speed': avgSpeed,
      };

  /// 총 볼륨 (Σ 무게 × 횟수, kg). cardio는 0.
  double get volume => sets.fold<double>(0, (sum, s) => sum + s.weight * s.reps);

  /// strength/cardio 규칙 검증. 문제가 있으면 [ArgumentError]를 던집니다.
  ///
  /// DB 스키마만으로는 "strength인데 거리가 들어있는" 경우를 막을 수 없어서
  /// 저장 전에 여기서 막습니다.
  void validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('종목 이름을 입력하세요.');
    }

    switch (type) {
      case ExerciseType.strength:
        if (durationMin != null || distanceKm != null || avgSpeed != null) {
          throw ArgumentError('근력 종목($name)에는 시간/거리/속도를 입력할 수 없습니다.');
        }
        if (sets.isEmpty) {
          throw ArgumentError('근력 종목($name)에 세트를 하나 이상 입력하세요.');
        }
        for (final workoutSet in sets) {
          workoutSet.validate();
        }
      case ExerciseType.cardio:
        if (sets.isNotEmpty) {
          throw ArgumentError('유산소 종목($name)에는 세트를 입력할 수 없습니다.');
        }
        if (durationMin == null && distanceKm == null) {
          throw ArgumentError('유산소 종목($name)에 시간 또는 거리를 입력하세요.');
        }
        for (final value in [durationMin, distanceKm, avgSpeed]) {
          if (value != null && value < 0) {
            throw ArgumentError('유산소 종목($name)의 값은 0 이상이어야 합니다.');
          }
        }
    }
  }
}

/// 근력 운동 세트 하나 (예: 60kg × 12회).
class WorkoutSet {
  const WorkoutSet({this.id, required this.weight, required this.reps});

  final int? id;

  /// kg. 맨몸 운동은 0.
  final double weight;
  final int reps;

  factory WorkoutSet.fromMap(Map<String, Object?> map) => WorkoutSet(
        id: readIntOrNull(map, 'id'),
        weight: readDouble(map, 'weight'),
        reps: readInt(map, 'reps'),
      );

  /// exercise_id와 set_number는 Repository가 저장할 때 채웁니다.
  Map<String, Object?> toMap() => {'weight': weight, 'reps': reps};

  void validate() {
    if (weight < 0) throw ArgumentError('무게는 0 이상이어야 합니다.');
    if (reps <= 0) throw ArgumentError('횟수는 1 이상이어야 합니다.');
  }
}

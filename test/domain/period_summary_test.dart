import 'dart:convert';

import 'package:fitmind/data/models/body_measurement.dart';
import 'package:fitmind/data/models/enums.dart';
import 'package:fitmind/data/models/meal.dart';
import 'package:fitmind/data/models/user_profile.dart';
import 'package:fitmind/data/models/workout.dart';
import 'package:fitmind/domain/period_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 7);

  const user = UserProfile(
    goal: Goal.muscleGain,
    gender: Gender.male,
    age: 27,
    height: 175,
    initialWeight: 70,
  );

  final measurements = [
    // 기간 밖 → 제외되어야 함
    BodyMeasurement(date: DateTime(2026, 9, 30), weight: 71.0),
    // 일부러 날짜 역순으로 넣어 정렬도 확인
    BodyMeasurement(date: DateTime(2026, 10, 7), weight: 69.2, bodyFat: 17.4),
    BodyMeasurement(date: DateTime(2026, 10, 4), weight: 69.6),
    BodyMeasurement(date: DateTime(2026, 10, 1), weight: 70.0, bodyFat: 18.0),
  ];

  final meals = [
    Meal(
      date: DateTime(2026, 10, 1),
      mealType: MealType.breakfast,
      foodText: '오트밀, 계란 2개',
      calories: 500,
      protein: 30,
      carbohydrate: 60,
      fat: 10,
    ),
    Meal(
      date: DateTime(2026, 10, 1),
      mealType: MealType.lunch,
      foodText: '닭가슴살 150g, 밥 한 공기',
      calories: 700,
      protein: 40,
      carbohydrate: 80,
      fat: 20,
    ),
    // 탄수화물 미입력 → avg_carbohydrate_g는 null이어야 함
    Meal(
      date: DateTime(2026, 10, 2),
      mealType: MealType.dinner,
      foodText: '연어 스테이크',
      calories: 800,
      protein: 50,
      fat: 25,
    ),
    // 기간 밖 → 제외
    Meal(
      date: DateTime(2026, 10, 8),
      mealType: MealType.lunch,
      foodText: '기간 밖',
      calories: 1000,
      protein: 100,
    ),
  ];

  final workouts = [
    Workout(
      date: DateTime(2026, 10, 1),
      exercises: const [
        WorkoutExercise.strength(name: 'Chest Press', sets: [
          WorkoutSet(weight: 60, reps: 12),
          WorkoutSet(weight: 65, reps: 10),
        ]),
        WorkoutExercise.cardio(name: 'Treadmill', durationMin: 20, distanceKm: 3),
      ],
    ),
    Workout(
      date: DateTime(2026, 10, 3),
      exercises: const [
        // 대소문자/공백이 달라도 같은 종목으로 묶여야 함
        WorkoutExercise.strength(name: 'chest press ', sets: [
          WorkoutSet(weight: 65, reps: 8),
        ]),
        WorkoutExercise.strength(name: 'Lat Pulldown', sets: [
          WorkoutSet(weight: 50, reps: 12),
        ]),
      ],
    ),
    // 같은 날 두 번째 세션 (일수는 중복 집계되면 안 됨)
    Workout(
      date: DateTime(2026, 10, 3),
      exercises: const [
        WorkoutExercise.cardio(name: 'Treadmill', durationMin: 15),
      ],
    ),
  ];

  Map<String, Object?> summarize() => buildPeriodSummary(
        start: start,
        end: end,
        user: user,
        measurements: measurements,
        meals: meals,
        workouts: workouts,
      );

  test('기간 정보', () {
    expect(summarize()['period'], {
      'start': '2026-10-01',
      'end': '2026-10-07',
      'days': 7,
    });
  });

  test('신체: 기간 내 기록만 날짜순으로 시작/끝/변화량', () {
    final body = summarize()['body'] as Map<String, Object?>;

    expect(body['measurement_days'], 3);
    expect(body['weight_kg'], {
      'start': 70.0,
      'end': 69.2,
      'change': -0.8,
      'records': 3,
    });
    expect(body['body_fat_pct'], {
      'start': 18.0,
      'end': 17.4,
      'change': -0.6,
      'records': 2,
    });
    expect(body['skeletal_muscle_kg'], isNull);
  });

  test('식단: 기록한 날 기준 평균, 일부 미입력 항목은 null', () {
    final diet = summarize()['diet'] as Map<String, Object?>;

    expect(diet['logged_days'], 2);
    expect(diet['meals'], 3);
    expect(diet['avg_meals_per_logged_day'], 1.5);
    expect(diet['avg_calories_kcal'], 1000.0);
    expect(diet['avg_protein_g'], 60.0);
    expect(diet['avg_carbohydrate_g'], isNull);
    expect(diet['avg_fat_g'], 27.5);
    // 60g ÷ 기간 마지막 체중 69.2kg
    expect(diet['protein_g_per_kg'], 0.87);
  });

  test('운동: 세션/일수/볼륨/종목별 집계', () {
    final exercise = summarize()['exercise'] as Map<String, Object?>;

    expect(exercise['sessions'], 3);
    expect(exercise['workout_days'], 2);
    expect(exercise['strength_days'], 2);
    expect(exercise['cardio_days'], 2);

    final strength = exercise['strength'] as Map<String, Object?>;
    expect(strength['total_sets'], 4);
    expect(strength['total_volume_kg'], 2490.0);
    expect(strength['by_exercise'], [
      {
        'name': 'Chest Press',
        'days': 2,
        'sets': 3,
        'max_weight_kg': 65.0,
        'volume_kg': 1890.0,
      },
      {
        'name': 'Lat Pulldown',
        'days': 1,
        'sets': 1,
        'max_weight_kg': 50.0,
        'volume_kg': 600.0,
      },
    ]);

    final cardio = exercise['cardio'] as Map<String, Object?>;
    expect(cardio['total_minutes'], 35.0);
    expect(cardio['total_distance_km'], 3.0);
    expect(cardio['by_exercise'], [
      {'name': 'Treadmill', 'days': 2, 'minutes': 35.0, 'distance_km': 3.0},
    ]);
  });

  test('JSON으로 변환 가능하다 (input_summary로 저장되므로)', () {
    expect(() => jsonEncode(summarize()), returnsNormally);
  });

  test('데이터가 없으면 평균값은 null, 개수는 0', () {
    final summary = buildPeriodSummary(
      start: start,
      end: end,
      user: null,
      measurements: const [],
      meals: const [],
      workouts: const [],
    );

    expect(summary['user'], isNull);
    final body = summary['body'] as Map<String, Object?>;
    expect(body['weight_kg'], isNull);
    final diet = summary['diet'] as Map<String, Object?>;
    expect(diet['logged_days'], 0);
    expect(diet['avg_calories_kcal'], isNull);
    final exercise = summary['exercise'] as Map<String, Object?>;
    expect(exercise['sessions'], 0);
  });

  test('끝 날짜가 시작보다 빠르면 실패한다', () {
    expect(
      () => buildPeriodSummary(
        start: end,
        end: start,
        user: user,
        measurements: const [],
        meals: const [],
        workouts: const [],
      ),
      throwsArgumentError,
    );
  });
}

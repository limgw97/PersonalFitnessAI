import 'package:fitmind/data/db/app_database.dart';
import 'package:fitmind/data/models/body_measurement.dart';
import 'package:fitmind/data/models/enums.dart';
import 'package:fitmind/data/models/meal.dart';
import 'package:fitmind/data/models/user_profile.dart';
import 'package:fitmind/data/models/workout.dart';
import 'package:fitmind/data/repositories/body_measurement_repository.dart';
import 'package:fitmind/data/repositories/meal_repository.dart';
import 'package:fitmind/data/repositories/user_repository.dart';
import 'package:fitmind/data/repositories/workout_repository.dart';
import 'package:fitmind/domain/period_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() async => db.close());

  Future<int> countRows(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return rows.first['n'] as int;
  }

  group('UserRepository', () {
    const profile = UserProfile(
      goal: Goal.fatLoss,
      gender: Gender.male,
      age: 27,
      height: 175,
      initialWeight: 70,
    );

    test('초기 설정 전에는 null', () async {
      expect(await UserRepository(db).get(), isNull);
    });

    test('저장 후 다시 저장하면 수정되고 행은 하나뿐이다', () async {
      final repo = UserRepository(db);
      await repo.save(profile);
      await repo.save(const UserProfile(
        goal: Goal.muscleGain,
        gender: Gender.male,
        age: 28,
        height: 175,
        initialWeight: 70,
      ));

      final saved = (await repo.get())!;
      expect(saved.goal, Goal.muscleGain);
      expect(saved.age, 28);
      expect(await countRows('user'), 1);
    });

    test('잘못된 값은 저장하지 않는다', () async {
      const invalid = UserProfile(
        goal: Goal.fatLoss,
        gender: Gender.male,
        age: 0,
        height: 175,
        initialWeight: 70,
      );
      await expectLater(UserRepository(db).save(invalid), throwsArgumentError);
      expect(await countRows('user'), 0);
    });
  });

  group('BodyMeasurementRepository', () {
    test('같은 날짜로 다시 저장하면 수정된다', () async {
      final repo = BodyMeasurementRepository(db);
      final day = DateTime(2026, 10, 11);

      await repo.save(BodyMeasurement(date: day, weight: 64.2));
      await repo.save(BodyMeasurement(date: day, weight: 64.0, bodyFat: 15.1));

      final saved = (await repo.getByDate(day))!;
      expect(saved.weight, 64.0);
      expect(saved.bodyFat, 15.1);
      expect(await countRows('body_measurement'), 1);
    });

    test('기간 조회는 양 끝을 포함하고 날짜순이다', () async {
      final repo = BodyMeasurementRepository(db);
      for (final day in [3, 1, 2, 5]) {
        await repo.save(
          BodyMeasurement(date: DateTime(2026, 10, day), weight: 60.0 + day),
        );
      }

      final range = await repo.getRange(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
      expect(range.map((m) => m.date.day), [1, 2, 3]);
    });

    test('날짜로 삭제', () async {
      final repo = BodyMeasurementRepository(db);
      final day = DateTime(2026, 10, 11);
      await repo.save(BodyMeasurement(date: day, weight: 64.2));

      expect(await repo.deleteByDate(day), 1);
      expect(await repo.getByDate(day), isNull);
    });
  });

  group('MealRepository', () {
    Meal lunch({int? id, double calories = 700}) => Meal(
          id: id,
          date: DateTime(2026, 10, 11),
          mealType: MealType.lunch,
          foodText: '닭가슴살 150g, 밥 한 공기',
          calories: calories,
          protein: 45,
        );

    test('추가, 조회, 수정, 삭제', () async {
      final repo = MealRepository(db);

      final id = await repo.add(lunch());
      expect((await repo.getByDate(DateTime(2026, 10, 11))).single.calories, 700);

      expect(await repo.update(lunch(id: id, calories: 650)), 1);
      expect((await repo.getByDate(DateTime(2026, 10, 11))).single.calories, 650);

      expect(await repo.delete(id), 1);
      expect(await repo.getByDate(DateTime(2026, 10, 11)), isEmpty);
    });

    test('id 없이 수정하면 실패한다', () async {
      await expectLater(MealRepository(db).update(lunch()), throwsArgumentError);
    });

    test('음수 칼로리는 저장하지 않는다', () async {
      await expectLater(
        MealRepository(db).add(lunch(calories: -1)),
        throwsArgumentError,
      );
      expect(await countRows('meal'), 0);
    });
  });

  group('WorkoutRepository', () {
    final day = DateTime(2026, 10, 11);

    Workout sample({int? id}) => Workout(
          id: id,
          date: day,
          memo: '저녁 운동',
          exercises: const [
            WorkoutExercise.strength(name: 'Chest Press', sets: [
              WorkoutSet(weight: 60, reps: 12),
              WorkoutSet(weight: 65, reps: 10),
              WorkoutSet(weight: 65, reps: 8),
            ]),
            WorkoutExercise.cardio(
              name: 'Treadmill',
              durationMin: 20,
              distanceKm: 3,
              avgSpeed: 9,
            ),
            WorkoutExercise.strength(name: 'Lat Pulldown', sets: [
              WorkoutSet(weight: 50, reps: 12),
            ]),
          ],
        );

    test('종목·세트까지 저장하고 순서대로 다시 읽는다', () async {
      final repo = WorkoutRepository(db);
      final id = await repo.save(sample());

      final saved = (await repo.getById(id))!;
      expect(saved.memo, '저녁 운동');
      expect(saved.exercises.map((e) => e.name),
          ['Chest Press', 'Treadmill', 'Lat Pulldown']);

      final chest = saved.exercises[0];
      expect(chest.type, ExerciseType.strength);
      expect(chest.sets.map((s) => '${s.weight}x${s.reps}'),
          ['60.0x12', '65.0x10', '65.0x8']);

      final treadmill = saved.exercises[1];
      expect(treadmill.type, ExerciseType.cardio);
      expect(treadmill.sets, isEmpty);
      expect(treadmill.durationMin, 20);
      expect(treadmill.distanceKm, 3);

      // set_number는 1부터 순서대로
      final setNumbers = await db.rawQuery(
        'SELECT set_number FROM workout_set ORDER BY id',
      );
      expect(setNumbers.map((r) => r['set_number']), [1, 2, 3, 1]);
    });

    test('수정하면 종목·세트가 새 내용으로 바뀐다', () async {
      final repo = WorkoutRepository(db);
      final id = await repo.save(sample());

      await repo.save(Workout(
        id: id,
        date: day,
        exercises: const [
          WorkoutExercise.strength(name: 'Squat', sets: [
            WorkoutSet(weight: 80, reps: 5),
          ]),
        ],
      ));

      final saved = (await repo.getById(id))!;
      expect(saved.memo, isNull);
      expect(saved.exercises.single.name, 'Squat');
      expect(await countRows('workout_exercise'), 1);
      expect(await countRows('workout_set'), 1);
    });

    test('없는 id를 수정하면 실패하고 아무것도 저장되지 않는다', () async {
      await expectLater(
        WorkoutRepository(db).save(sample(id: 999)),
        throwsStateError,
      );
      expect(await countRows('workout'), 0);
      expect(await countRows('workout_exercise'), 0);
    });

    test('근력 종목에 거리를 넣으면 저장하지 않는다', () async {
      final invalid = Workout(date: day, exercises: const [
        WorkoutExercise(
          name: 'Chest Press',
          type: ExerciseType.strength,
          distanceKm: 1,
          sets: [WorkoutSet(weight: 60, reps: 10)],
        ),
      ]);

      await expectLater(WorkoutRepository(db).save(invalid), throwsArgumentError);
      expect(await countRows('workout'), 0);
    });

    test('유산소 종목에 세트를 넣으면 저장하지 않는다', () async {
      final invalid = Workout(date: day, exercises: const [
        WorkoutExercise(
          name: 'Treadmill',
          type: ExerciseType.cardio,
          durationMin: 20,
          sets: [WorkoutSet(weight: 0, reps: 1)],
        ),
      ]);

      await expectLater(WorkoutRepository(db).save(invalid), throwsArgumentError);
    });

    test('삭제하면 종목·세트도 함께 삭제된다', () async {
      final repo = WorkoutRepository(db);
      final id = await repo.save(sample());

      expect(await repo.delete(id), 1);
      expect(await countRows('workout_exercise'), 0);
      expect(await countRows('workout_set'), 0);
    });

    test('기간 조회는 여러 날짜의 세션을 날짜순으로 돌려준다', () async {
      final repo = WorkoutRepository(db);
      for (final d in [5, 1, 3]) {
        await repo.save(Workout(date: DateTime(2026, 10, d), exercises: const [
          WorkoutExercise.cardio(name: 'Treadmill', durationMin: 10),
        ]));
      }

      final range =
          await repo.getRange(DateTime(2026, 10, 1), DateTime(2026, 10, 4));
      expect(range.map((w) => w.date.day), [1, 3]);
      expect(range.every((w) => w.exercises.length == 1), isTrue);
    });
  });

  test('PeriodSummaryService: DB에 저장한 데이터로 요약을 만든다', () async {
    final users = UserRepository(db);
    final measurements = BodyMeasurementRepository(db);
    final meals = MealRepository(db);
    final workouts = WorkoutRepository(db);

    await users.save(const UserProfile(
      goal: Goal.fatLoss,
      gender: Gender.male,
      age: 27,
      height: 175,
      initialWeight: 70,
    ));
    await measurements.save(BodyMeasurement(date: DateTime(2026, 10, 1), weight: 70));
    await measurements.save(BodyMeasurement(date: DateTime(2026, 10, 7), weight: 69.5));
    await meals.add(Meal(
      date: DateTime(2026, 10, 2),
      mealType: MealType.lunch,
      foodText: '닭가슴살 샐러드',
      calories: 600,
      protein: 50,
    ));
    await workouts.save(Workout(date: DateTime(2026, 10, 3), exercises: const [
      WorkoutExercise.strength(name: 'Squat', sets: [
        WorkoutSet(weight: 80, reps: 5),
      ]),
    ]));

    final summary = await PeriodSummaryService(
      users: users,
      measurements: measurements,
      meals: meals,
      workouts: workouts,
    ).summarize(DateTime(2026, 10, 1), DateTime(2026, 10, 7));

    final body = summary['body'] as Map<String, Object?>;
    expect((body['weight_kg'] as Map)['change'], -0.5);
    final diet = summary['diet'] as Map<String, Object?>;
    expect(diet['avg_calories_kcal'], 600.0);
    final exercise = summary['exercise'] as Map<String, Object?>;
    expect((exercise['strength'] as Map)['total_volume_kg'], 400.0);
  });
}

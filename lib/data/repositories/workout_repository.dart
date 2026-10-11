import 'package:sqflite/sqflite.dart';

import '../../core/db_date.dart';
import '../models/workout.dart';

/// 운동 기록 저장소.
///
/// Workout / WorkoutExercise / WorkoutSet 세 테이블을 항상 한 덩어리로 다룹니다.
/// 화면에서는 "운동 세션 하나"만 신경 쓰면 되도록 하는 게 목적입니다.
class WorkoutRepository {
  WorkoutRepository(this._db);

  // 저장은 트랜잭션이 필요해서 DatabaseExecutor가 아니라 Database를 받습니다.
  final Database _db;

  /// 운동 세션을 종목·세트까지 통째로 저장하고 workout id를 돌려줍니다.
  ///
  /// - [workout.id]가 null이면 새로 생성
  /// - id가 있으면 기존 세션을 수정: 종목/세트는 전부 지우고 새로 저장
  ///   (V1에서는 단순함을 위해 이 방식. 수정 후 종목/세트 id는 바뀝니다)
  ///
  /// 전체가 하나의 트랜잭션이라 중간에 실패하면 아무것도 저장되지 않습니다.
  Future<int> save(Workout workout) async {
    workout.validate();

    return _db.transaction<int>((txn) async {
      final int workoutId;
      final existingId = workout.id;

      if (existingId == null) {
        workoutId = await txn.insert('workout', workout.toMap());
      } else {
        final updated = await txn.update(
          'workout',
          workout.toMap(),
          where: 'id = ?',
          whereArgs: [existingId],
        );
        if (updated == 0) {
          throw StateError('운동 기록(id=$existingId)이 없습니다.');
        }
        // ON DELETE CASCADE로 세트도 함께 삭제됨
        await txn.delete(
          'workout_exercise',
          where: 'workout_id = ?',
          whereArgs: [existingId],
        );
        workoutId = existingId;
      }

      for (var i = 0; i < workout.exercises.length; i++) {
        final exercise = workout.exercises[i];
        final exerciseId = await txn.insert('workout_exercise', {
          ...exercise.toMap(),
          'workout_id': workoutId,
          'order_index': i,
        });

        for (var j = 0; j < exercise.sets.length; j++) {
          await txn.insert('workout_set', {
            ...exercise.sets[j].toMap(),
            'exercise_id': exerciseId,
            'set_number': j + 1,
          });
        }
      }

      return workoutId;
    });
  }

  /// 운동 세션 삭제 (종목·세트도 CASCADE로 함께 삭제). 지운 행 수.
  Future<int> delete(int id) =>
      _db.delete('workout', where: 'id = ?', whereArgs: [id]);

  Future<Workout?> getById(int id) async {
    final list = await _load('w.id = ?', [id]);
    return list.isEmpty ? null : list.first;
  }

  Future<List<Workout>> getByDate(DateTime date) => getRange(date, date);

  /// [start]~[end] (양 끝 포함) 운동 세션을 날짜 → 입력 순서로, 종목·세트 포함.
  Future<List<Workout>> getRange(DateTime start, DateTime end) =>
      _load('w.date BETWEEN ? AND ?', [toDbDate(start), toDbDate(end)]);

  /// workout 조건([where], 별칭 `w`)에 맞는 세션을 종목·세트까지 조립합니다.
  ///
  /// 세션마다 쿼리를 따로 날리지 않고 테이블별로 한 번씩, 총 3번만 조회합니다.
  /// `IN (?, ?, ...)` 대신 JOIN을 쓰는 이유: 구형 SQLite는 ? 개수가 999개로
  /// 제한되어 있어서, 1년치처럼 기간이 길면 IN 방식은 실패할 수 있습니다.
  Future<List<Workout>> _load(String where, List<Object?> args) async {
    final workoutRows = await _db.rawQuery(
      'SELECT w.* FROM workout w WHERE $where ORDER BY w.date ASC, w.id ASC',
      args,
    );
    if (workoutRows.isEmpty) return [];

    final exerciseRows = await _db.rawQuery(
      'SELECT e.* FROM workout_exercise e '
      'JOIN workout w ON e.workout_id = w.id '
      'WHERE $where ORDER BY e.workout_id ASC, e.order_index ASC',
      args,
    );

    final setRows = await _db.rawQuery(
      'SELECT s.* FROM workout_set s '
      'JOIN workout_exercise e ON s.exercise_id = e.id '
      'JOIN workout w ON e.workout_id = w.id '
      'WHERE $where ORDER BY s.exercise_id ASC, s.set_number ASC',
      args,
    );

    final setsByExercise = <int, List<WorkoutSet>>{};
    for (final row in setRows) {
      final exerciseId = (row['exercise_id'] as num).toInt();
      setsByExercise.putIfAbsent(exerciseId, () => []).add(WorkoutSet.fromMap(row));
    }

    final exercisesByWorkout = <int, List<WorkoutExercise>>{};
    for (final row in exerciseRows) {
      final exerciseId = (row['id'] as num).toInt();
      final workoutId = (row['workout_id'] as num).toInt();
      exercisesByWorkout.putIfAbsent(workoutId, () => []).add(
            WorkoutExercise.fromMap(
              row,
              sets: setsByExercise[exerciseId] ?? const [],
            ),
          );
    }

    return [
      for (final row in workoutRows)
        Workout.fromMap(
          row,
          exercises:
              exercisesByWorkout[(row['id'] as num).toInt()] ?? const [],
        ),
    ];
  }
}

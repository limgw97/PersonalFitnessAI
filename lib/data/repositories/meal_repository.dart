import 'package:sqflite/sqflite.dart';

import '../../core/db_date.dart';
import '../models/meal.dart';

/// 식사 기록 저장소. 하루에 여러 끼를 저장할 수 있습니다.
class MealRepository {
  MealRepository(this._db);

  final DatabaseExecutor _db;

  static const _table = 'meal';

  /// 새 식사를 추가하고 생성된 id를 돌려줍니다.
  Future<int> add(Meal meal) async {
    meal.validate();
    return _db.insert(_table, meal.toMap());
  }

  /// 기존 식사를 수정합니다. [meal.id]가 없으면 [ArgumentError].
  /// 수정된 행 수 (0이면 해당 id가 없었음).
  Future<int> update(Meal meal) async {
    final id = meal.id;
    if (id == null) throw ArgumentError('수정할 식사의 id가 없습니다.');
    meal.validate();
    return _db.update(_table, meal.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) =>
      _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  /// 하루치 식사 (끼니 입력 순서대로).
  Future<List<Meal>> getByDate(DateTime date) => getRange(date, date);

  /// [start]~[end] (양 끝 포함) 식사를 날짜 → 입력 순서로.
  Future<List<Meal>> getRange(DateTime start, DateTime end) async {
    final rows = await _db.query(
      _table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [toDbDate(start), toDbDate(end)],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(Meal.fromMap).toList();
  }
}

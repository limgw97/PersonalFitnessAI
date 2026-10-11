import 'package:sqflite/sqflite.dart';

import '../../core/db_date.dart';
import '../models/body_measurement.dart';

/// 신체 측정 기록 저장소. 하루에 한 기록만 존재합니다.
class BodyMeasurementRepository {
  BodyMeasurementRepository(this._db);

  final DatabaseExecutor _db;

  static const _table = 'body_measurement';

  /// 해당 날짜 기록이 있으면 수정, 없으면 생성합니다.
  /// (구형 Android SQLite 호환을 위해 UPDATE → INSERT 순서. UserRepository 참고)
  Future<void> save(BodyMeasurement measurement) async {
    measurement.validate();
    final values = measurement.toMap();
    final date = values['date'];

    final updated = await _db.update(
      _table,
      values,
      where: 'date = ?',
      whereArgs: [date],
    );
    if (updated == 0) {
      await _db.insert(_table, values);
    }
  }

  Future<BodyMeasurement?> getByDate(DateTime date) async {
    final rows = await _db.query(
      _table,
      where: 'date = ?',
      whereArgs: [toDbDate(date)],
    );
    return rows.isEmpty ? null : BodyMeasurement.fromMap(rows.first);
  }

  /// [start]~[end] (양 끝 포함) 기록을 날짜순으로.
  Future<List<BodyMeasurement>> getRange(DateTime start, DateTime end) async {
    final rows = await _db.query(
      _table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [toDbDate(start), toDbDate(end)],
      orderBy: 'date ASC',
    );
    return rows.map(BodyMeasurement.fromMap).toList();
  }

  /// 지운 행 수 (0 또는 1).
  Future<int> deleteByDate(DateTime date) => _db.delete(
        _table,
        where: 'date = ?',
        whereArgs: [toDbDate(date)],
      );
}

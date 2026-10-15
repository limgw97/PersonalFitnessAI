import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';

/// 사용자 정보 저장소. DB에는 id = 1인 한 행만 존재합니다.
class UserRepository {
  UserRepository(this._db);

  final DatabaseExecutor _db;

  static const _table = 'user';
  static const _id = 1;

  /// 저장된 사용자 정보. 아직 초기 설정을 안 했으면 null.
  Future<UserProfile?> get() async {
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [_id]);
    return rows.isEmpty ? null : UserProfile.fromMap(rows.first);
  }

  /// 있으면 수정, 없으면 생성합니다.
  ///
  /// `INSERT ... ON CONFLICT DO UPDATE`(upsert)는 SQLite 3.24 이상에서만 되는데
  /// 구형 Android 기기의 SQLite는 그보다 낮을 수 있어서, UPDATE를 먼저 시도하고
  /// 바뀐 행이 없으면 INSERT하는 방식을 씁니다. (created_at도 처음 값이 유지됨)
  Future<void> save(UserProfile profile) async {
    profile.validate();
    final values = profile.toMap();

    final updated =
        await _db.update(_table, values, where: 'id = ?', whereArgs: [_id]);
    if (updated == 0) {
      await _db.insert(_table, {'id': _id, ...values});
    }
  }
}

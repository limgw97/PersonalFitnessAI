import 'package:sqflite/sqflite.dart';

import 'schema_v1.dart';

/// 한 버전으로 올라가는 마이그레이션 하나.
typedef Migration = Future<void> Function(DatabaseExecutor db);

/// 버전별 마이그레이션 목록.
///
/// 키 N의 마이그레이션은 DB를 "버전 N-1 → 버전 N"으로 올립니다.
/// 키 1은 빈 DB에서 v1 스키마를 만드는 초기 생성입니다.
///
/// 스키마를 바꿀 때:
///   1. 여기에 다음 번호(예: 2)로 마이그레이션을 추가
///   2. 기존 마이그레이션은 절대 수정하지 않음 (이미 설치된 사용자 DB가 그 결과물)
///   3. `docs/schema.sql`도 최신 구조로 갱신
final Map<int, Migration> migrations = {
  1: (db) async {
    for (final statement in schemaV1) {
      await db.execute(statement);
    }
  },
  // 2: (db) async {
  //   await db.execute('ALTER TABLE meal ADD COLUMN ...');
  // },
};

/// 현재 앱이 기대하는 최신 스키마 버전.
int get latestSchemaVersion =>
    migrations.keys.reduce((a, b) => a > b ? a : b);

/// [fromVersion] 다음 버전부터 [toVersion]까지 마이그레이션을 순서대로 실행합니다.
///
/// 중간 버전의 마이그레이션이 하나라도 빠져 있으면 실행 전에 [StateError]를 던집니다.
/// (예: 1, 3만 있고 2가 없으면 v1 사용자는 v3로 올라갈 수 없음)
Future<void> runMigrations(
  DatabaseExecutor db, {
  required int fromVersion,
  required int toVersion,
  Map<int, Migration>? registry,
}) async {
  final steps = registry ?? migrations;

  for (var v = fromVersion + 1; v <= toVersion; v++) {
    if (!steps.containsKey(v)) {
      throw StateError('v$v 마이그레이션이 없습니다 (v$fromVersion → v$toVersion).');
    }
  }

  for (var v = fromVersion + 1; v <= toVersion; v++) {
    await steps[v]!(db);
  }
}

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// 앱의 SQLite DB를 열고, 필요한 마이그레이션을 적용합니다.
///
/// 스키마 버전은 SQLite 파일 헤더의 `PRAGMA user_version`에 저장됩니다.
/// (sqflite의 `version` 옵션이 이 값을 관리)
/// 버전이 DB 파일 안에 들어 있으므로 `.db` 파일을 백업/복원해도 함께 따라갑니다.
class AppDatabase {
  AppDatabase._();

  static const String fileName = 'fitmind.db';

  /// DB를 엽니다.
  ///
  /// - [factory]: 테스트에서는 `databaseFactoryFfi`를 넘깁니다. 생략하면 기기 기본값.
  /// - [path]: 테스트에서는 `inMemoryDatabasePath`를 넘깁니다. 생략하면 앱 DB 경로.
  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), fileName);

    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: latestSchemaVersion,
        // SQLite는 외래키 검사가 기본으로 꺼져 있고, 연결마다 켜야 합니다.
        // 이게 없으면 ON DELETE CASCADE가 오류 없이 조용히 무시됩니다.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        // onCreate / onUpgrade는 sqflite가 트랜잭션 안에서 실행합니다.
        // 중간에 실패하면 전체가 롤백되고 user_version도 올라가지 않습니다.
        onCreate: (db, version) =>
            runMigrations(db, fromVersion: 0, toVersion: version),
        onUpgrade: (db, oldVersion, newVersion) =>
            runMigrations(db, fromVersion: oldVersion, toVersion: newVersion),
        // 더 새 버전 앱에서 만든 백업을 구버전 앱에서 열려는 경우.
        // 조용히 열면 데이터가 깨질 수 있으므로 명확하게 실패시킵니다.
        onDowngrade: (db, oldVersion, newVersion) {
          throw UnsupportedError(
            'DB 버전(v$oldVersion)이 앱이 지원하는 버전(v$newVersion)보다 높습니다. '
            '앱을 최신 버전으로 업데이트하세요.',
          );
        },
      ),
    );
  }
}

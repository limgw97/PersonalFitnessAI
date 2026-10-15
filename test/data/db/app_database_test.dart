import 'dart:io';

import 'package:fitmind/data/db/app_database.dart';
import 'package:fitmind/data/db/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // 기기 없이 PC에서 SQLite를 돌리기 위한 FFI 초기화
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  group('AppDatabase.open (새 설치)', () {
    late Database db;

    setUp(() async {
      db = await AppDatabase.open(factory: factory, path: inMemoryDatabasePath);
    });

    tearDown(() async => db.close());

    test('user_version이 최신 스키마 버전으로 설정된다', () async {
      expect(await db.getVersion(), latestSchemaVersion);
    });

    test('v1 테이블이 모두 생성된다', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final tables = rows.map((r) => r['name'] as String).toSet();

      expect(tables, {
        'user',
        'body_measurement',
        'meal',
        'workout',
        'workout_exercise',
        'workout_set',
        'ai_analysis',
      });
    });

    test('외래키 검사가 켜져 있다', () async {
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.first.values.first, 1);
    });

    test('workout 삭제 시 exercise와 set이 함께 삭제된다 (CASCADE)', () async {
      final workoutId = await db.insert('workout', {'date': '2026-10-11'});
      final exerciseId = await db.insert('workout_exercise', {
        'workout_id': workoutId,
        'exercise_name': 'Chest Press',
        'exercise_type': 'strength',
        'order_index': 0,
      });
      await db.insert('workout_set', {
        'exercise_id': exerciseId,
        'set_number': 1,
        'weight': 60,
        'reps': 12,
      });

      await db.delete('workout', where: 'id = ?', whereArgs: [workoutId]);

      expect(await db.query('workout_exercise'), isEmpty);
      expect(await db.query('workout_set'), isEmpty);
    });

    test('존재하지 않는 workout을 참조하는 exercise는 거부된다', () async {
      expect(
        () => db.insert('workout_exercise', {
          'workout_id': 999,
          'exercise_name': 'Treadmill',
          'exercise_type': 'cardio',
          'order_index': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('user는 id = 1인 한 행만 허용된다', () async {
      final profile = {
        'goal': 'fat_loss',
        'gender': 'male',
        'age': 27,
        'height': 175.0,
        'initial_weight': 70.0,
      };
      await db.insert('user', {'id': 1, ...profile});

      expect(
        () => db.insert('user', {'id': 2, ...profile}),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('body_measurement는 같은 날짜를 두 번 저장할 수 없다', () async {
      await db.insert('body_measurement', {'date': '2026-10-11', 'weight': 64.2});

      expect(
        () => db.insert(
          'body_measurement',
          {'date': '2026-10-11', 'weight': 64.0},
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('runMigrations', () {
    late Database db;

    setUp(() async {
      db = await factory.openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async => db.close());

    test('현재 버전 다음부터 순서대로 실행한다', () async {
      final executed = <int>[];
      final registry = <int, Migration>{
        1: (_) async => executed.add(1),
        2: (_) async => executed.add(2),
        3: (_) async => executed.add(3),
      };

      await runMigrations(db, fromVersion: 1, toVersion: 3, registry: registry);

      expect(executed, [2, 3]);
    });

    test('중간 마이그레이션이 빠져 있으면 아무것도 실행하지 않고 실패한다', () async {
      final executed = <int>[];
      final registry = <int, Migration>{
        1: (_) async => executed.add(1),
        3: (_) async => executed.add(3),
      };

      await expectLater(
        runMigrations(db, fromVersion: 0, toVersion: 3, registry: registry),
        throwsStateError,
      );
      expect(executed, isEmpty);
    });
  });

  test('더 새 버전의 DB 파일을 열면 명확한 오류로 실패한다', () async {
    final dir = await Directory.systemTemp.createTemp('fitmind_test_');
    final path = p.join(dir.path, 'future.db');

    try {
      // 미래 버전 앱이 만든 백업 파일을 흉내냄
      final future = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: latestSchemaVersion + 1),
      );
      await future.close();

      await expectLater(
        AppDatabase.open(factory: factory, path: path),
        throwsA(isA<UnsupportedError>()),
      );
    } finally {
      // Windows에서 파일 핸들이 늦게 풀리는 경우가 있어 정리 실패는 무시
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}

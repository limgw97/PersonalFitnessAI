/// FitMind SQLite 스키마 v1.
///
/// 이 파일의 SQL은 `docs/schema.sql`과 항상 같은 내용이어야 합니다.
/// 스키마를 바꿀 때는 이 파일을 수정하지 말고, `migrations.dart`에
/// 새 버전(v2, v3, ...)의 마이그레이션을 추가하세요.
/// (v1은 이미 설치된 사용자의 DB 구조를 뜻하므로 바뀌면 안 됩니다.)
library;

const List<String> schemaV1 = [
  // User: 단일 row만 존재 (멀티유저 아님)
  '''
  CREATE TABLE user (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    goal TEXT NOT NULL,
    gender TEXT NOT NULL,
    age INTEGER NOT NULL,
    height REAL NOT NULL,
    initial_weight REAL NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',

  // BodyMeasurement: 하루 1행
  '''
  CREATE TABLE body_measurement (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    weight REAL NOT NULL,
    body_fat REAL,
    skeletal_muscle REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',

  // Meal: 자유 텍스트 + 영양정보 수동 입력
  '''
  CREATE TABLE meal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    meal_type TEXT NOT NULL,
    food_text TEXT NOT NULL,
    calories REAL NOT NULL,
    protein REAL NOT NULL,
    carbohydrate REAL,
    fat REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',
  'CREATE INDEX idx_meal_date ON meal(date)',

  // Workout
  '''
  CREATE TABLE workout (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    memo TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',
  'CREATE INDEX idx_workout_date ON workout(date)',

  // WorkoutExercise: cardio 필드는 strength일 때 전부 NULL
  // (strength/cardio 정합성은 Repository 레이어에서 검증)
  '''
  CREATE TABLE workout_exercise (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL,
    exercise_name TEXT NOT NULL,
    exercise_type TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    duration_min REAL,
    distance_km REAL,
    avg_speed REAL,
    FOREIGN KEY (workout_id) REFERENCES workout(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_workout_exercise_workout_id ON workout_exercise(workout_id)',

  // WorkoutSet: strength 전용
  '''
  CREATE TABLE workout_set (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    exercise_id INTEGER NOT NULL,
    set_number INTEGER NOT NULL,
    weight REAL NOT NULL,
    reps INTEGER NOT NULL,
    FOREIGN KEY (exercise_id) REFERENCES workout_exercise(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_workout_set_exercise_id ON workout_set(exercise_id)',

  // AIAnalysis
  '''
  CREATE TABLE ai_analysis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    input_summary TEXT NOT NULL,
    analysis_result TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_ai_analysis_period ON ai_analysis(period_start, period_end)',
];

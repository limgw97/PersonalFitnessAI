-- FitMind SQLite Schema v1
-- 앱 코드의 원본: lib/data/db/schema_v1.dart (두 파일은 항상 같은 내용이어야 함)
--
-- 연결할 때마다 반드시 실행: PRAGMA foreign_keys = ON;
-- 스키마 버전: 별도 테이블 없이 SQLite 헤더의 PRAGMA user_version으로 관리
--   (sqflite의 version 옵션이 관리, 마이그레이션은 lib/data/db/migrations.dart)

-- ============================================
-- User (단일 row만 존재 — 멀티유저 아님)
-- ============================================
CREATE TABLE user (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  goal TEXT NOT NULL,             -- 'fat_loss' | 'muscle_gain' | 'maintenance' | 'endurance' | 'other'
  gender TEXT NOT NULL,           -- 'male' | 'female' | 'other'
  age INTEGER NOT NULL,
  height REAL NOT NULL,           -- cm
  initial_weight REAL NOT NULL,   -- kg
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================
-- BodyMeasurement (하루 1행)
-- ============================================
CREATE TABLE body_measurement (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,      -- 'YYYY-MM-DD'
  weight REAL NOT NULL,
  body_fat REAL,                  -- nullable
  skeletal_muscle REAL,           -- nullable
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
-- date의 UNIQUE 제약이 인덱스를 자동 생성하므로 별도 인덱스 없음

-- ============================================
-- Meal (V1: 자유 텍스트 + 영양정보 수동 입력)
-- ============================================
CREATE TABLE meal (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,             -- 'YYYY-MM-DD'
  meal_type TEXT NOT NULL,        -- 'breakfast' | 'lunch' | 'dinner' | 'snack'
  food_text TEXT NOT NULL,
  calories REAL NOT NULL,
  protein REAL NOT NULL,
  carbohydrate REAL,              -- nullable
  fat REAL,                       -- nullable
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_meal_date ON meal(date);

-- ============================================
-- Workout
-- ============================================
CREATE TABLE workout (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  memo TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_workout_date ON workout(date);

-- ============================================
-- WorkoutExercise
-- cardio 필드는 strength일 때 전부 NULL (정합성은 앱 레이어에서 검증)
-- ============================================
CREATE TABLE workout_exercise (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workout_id INTEGER NOT NULL,
  exercise_name TEXT NOT NULL,
  exercise_type TEXT NOT NULL,    -- 'strength' | 'cardio'
  order_index INTEGER NOT NULL,
  duration_min REAL,              -- cardio 전용
  distance_km REAL,               -- cardio 전용
  avg_speed REAL,                 -- cardio 전용
  FOREIGN KEY (workout_id) REFERENCES workout(id) ON DELETE CASCADE
);
CREATE INDEX idx_workout_exercise_workout_id ON workout_exercise(workout_id);

-- ============================================
-- WorkoutSet (strength 전용)
-- ============================================
CREATE TABLE workout_set (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exercise_id INTEGER NOT NULL,
  set_number INTEGER NOT NULL,
  weight REAL NOT NULL,
  reps INTEGER NOT NULL,
  FOREIGN KEY (exercise_id) REFERENCES workout_exercise(id) ON DELETE CASCADE
);
CREATE INDEX idx_workout_set_exercise_id ON workout_set(exercise_id);

-- ============================================
-- AIAnalysis
-- ============================================
CREATE TABLE ai_analysis (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  input_summary TEXT NOT NULL,    -- LLM에 보낸 통계 요약 (JSON 문자열)
  analysis_result TEXT NOT NULL   -- LLM 원문 응답
);
CREATE INDEX idx_ai_analysis_period ON ai_analysis(period_start, period_end);

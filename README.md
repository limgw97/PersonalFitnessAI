# FitMind

> LLM 기반 개인 맞춤형 식단·운동 관리 애플리케이션
> LLMベースのパーソナル食事・運動管理アプリケーション
> LLM-powered personal diet & workout management app

**[한국어](#한국어)** | **[日本語](#日本語)** | **[English](#english)**

---

## 한국어

### 프로젝트 개요

FitMind는 사용자의 운동·식단·신체 데이터를 기기 로컬 데이터베이스에 장기 보관하고, 사용자가 원하는 기간의 데이터를 LLM에 전달하여 변화 추이와 패턴을 분석 받는 개인 맞춤형 Fitness 관리 앱입니다.

단순히 LLM에게 운동이나 식단을 질문하는 것이 아니라 다음 흐름을 목표로 합니다.

```
사용자 데이터의 지속적인 축적
        ↓
구조화된 데이터 분석
        ↓
LLM을 통한 해석 및 피드백
```

### 핵심 설계 철학

**LLM을 "기억장치"로 사용하지 않는다.**

LLM이 이전 대화를 기억하지 못하더라도 사용자의 과거 데이터가 사라지지 않도록, 모든 원본 데이터는 기기의 로컬 SQLite 데이터베이스에 누적 저장합니다. LLM은 영구 저장소가 아니라 **분석 엔진**으로만 사용합니다.

```
Persistent User Data → Structured Data Processing → LLM Analysis → Actionable Feedback
```

### 아키텍처

#### V1 (Local MVP + 단일 LLM Provider)

```
Flutter App
 │
 ├── UI (캘린더 기반 입력/조회)
 │
 ├── SQLite
 │    ├── User
 │    ├── BodyMeasurement
 │    ├── Meal
 │    ├── Workout → WorkoutExercise → WorkoutSet
 │    └── AIAnalysis
 │
 ├── Statistics / Data Processing (기간별 통계 계산은 앱에서 선처리)
 │
 └── LLMService
      └── OpenAIService (V1 실구현)
           ↑
     사용자가 직접 API Key 등록 (BYOK)
     Key는 Secure Storage에 저장, SQLite에는 저장하지 않음
```

- **서버 없음.** 사용자가 자신의 LLM API Key를 직접 등록해서 사용하는 BYOK(Bring Your Own Key) 구조로, 개발자가 API 비용이나 서버를 운영할 필요가 없습니다.
- `LLMService` 인터페이스로 Provider를 추상화해두되, V1에서 실제로 구현하는 Provider는 **OpenAI 하나**로 제한합니다. 구조적 확장성은 확보하되 구현 범위는 통제하는 방향입니다.

#### 향후 확장 방향

```
LLMService
 ├── OpenAIService   (V1)
 ├── GeminiService   (확장)
 └── ClaudeService   (확장)
```

복수 LLM 병렬 분석, Provider별 역할 분배, 결과 비교 등은 V1 스코프에서 명확히 제외하고 이후 단계의 확장 기능으로 둡니다. 공개 배포 형태로 발전하거나 API Key를 클라이언트에 직접 두지 않는 구조가 필요해질 경우, FastAPI 기반 Stateless Proxy 도입도 선택지로 남겨둡니다.

```
(향후 선택적 확장)
Flutter → FastAPI Proxy → LLM Provider
```

### 데이터 흐름

```
SQLite 원본 데이터
      ↓
기간 선택 (최근 7일 / 14일 / 30일 / 사용자 지정)
      ↓
Flutter에서 통계 계산 (변화량, 평균 등)
      ↓
Structured Input Summary (JSON)
      ↓
LLM API
      ↓
자연어 분석 결과
      ↓
AIAnalysis 저장 (input_summary + analysis_result)
      ↓
UI 표시
```

계산 가능한 수치는 앱에서 먼저 계산하고, LLM은 패턴 해석과 자연어 피드백에 집중시킵니다.

### AI 피드백 범위

- 기간 총평
- 식단 분석 (평균 섭취량, 단백질 패턴, 식사 빈도, 목표 적합성)
- 운동 분석 (빈도, 근력/유산소 비율, 운동량 변화, 부위 편중 여부)
- 신체 변화 (체중/체지방/골격근 추세)
- 향후 방향 제안

### 데이터 저장 및 백업

**Local-first.** 모든 원본 데이터는 기기 내 SQLite에 저장됩니다.

- **백업/복원**: `.db` 파일 자체를 백업 단위로 사용합니다. 별도 포맷 변환 없이 SQLite DB 파일을 그대로 백업/복원합니다.
- **Export**: CSV/JSON은 기본 백업 방식이 아니라, 사용자가 데이터를 확인하거나 다른 프로그램에서 활용하기 위한 보조 기능으로 취급합니다.
- **Schema Migration**: 앱 최초 버전부터 `schema_version`을 관리하여, 앱 업데이트 이후에도 기존 사용자의 `.db` 파일이 정상적으로 유지되도록 합니다.

### DB 스키마 (요약)

```
User
BodyMeasurement
Meal
Workout
  └── WorkoutExercise (strength / cardio)
        └── WorkoutSet (strength 전용)
AIAnalysis (input_summary 포함 — 재현/디버깅/비교 목적)
```

- 운동 데이터는 `Workout → WorkoutExercise → WorkoutSet` 3단 구조로 분리하여, 세트별 기록(무게 × 반복 횟수)을 자연스럽게 저장합니다.
- Cardio는 V1에서 별도 테이블 없이 `WorkoutExercise`의 nullable 필드(duration/distance/speed)로 처리합니다.

전체 스키마 정의는 `/docs/schema.sql` 참고. *(추후 추가 예정)*

### 기술 스택

| 영역 | 선택 |
|---|---|
| App | Flutter |
| Local DB | SQLite |
| LLM (V1) | OpenAI API (BYOK) |
| API Key 저장 | Secure Storage (Android/iOS) |
| Server | 없음 (V1) |

### 개발 로드맵

- [ ] **Phase 1 — 설계**: 요구사항 정리, 화면 구성, DB 스키마, LLM 인터페이스 설계
- [ ] **Phase 2 — Local MVP**: Flutter + SQLite, 초기 설정, 캘린더, 식단/운동/신체 기록, Migration 구조
- [ ] **Phase 3 — LLM Integration**: LLMService 인터페이스, OpenAIService, 기간별 통계 → AI 분석
- [ ] **Phase 4 — Data Management**: `.db` 백업/복원, CSV/JSON Export, 데이터 검증
- [ ] **Phase 5 — 고도화**: 데이터 시각화, 장기 추세, AI 분석 이력 비교, 추가 LLM Provider(Gemini/Claude), 복수 LLM 병렬 분석, 결과 비교, 식품 DB/API 연동, LLM-assisted 식단 입력

### 미확정 사항

- [ ] SQLite 라이브러리 선택 (sqflite 등)
- [ ] OpenAI 모델 선택 및 Prompt 구조
- [ ] AIAnalysis 결과 저장 포맷 (원문 TEXT vs 구조화 JSON)
- [ ] 체중/체지방/골격근 그래프 UI
- [ ] 안전한 `.db` 백업 방식 (복원 시 기존 데이터 덮어쓰기 방지 절차)

---

## 日本語

### プロジェクト概要

FitMindは、ユーザーの運動・食事・身体データを端末のローカルデータベースに長期保存し、ユーザーが指定した期間のデータをLLMに渡して変化の傾向やパターンを分析してもらう、パーソナライズされたフィットネス管理アプリです。

単にLLMに運動や食事について質問するのではなく、次のような流れを目指します。

```
ユーザーデータの継続的な蓄積
        ↓
構造化されたデータ分析
        ↓
LLMによる解釈とフィードバック
```

### 設計思想

**LLMを「記憶装置」として使わない。**

LLMが過去の会話を記憶していなくても、ユーザーの過去データが失われないように、すべての元データは端末内のローカルSQLiteデータベースに蓄積保存します。LLMは永続的なストレージではなく、**分析エンジン**としてのみ使用します。

```
Persistent User Data → Structured Data Processing → LLM Analysis → Actionable Feedback
```

### アーキテクチャ

#### V1（Local MVP + 単一LLM Provider）

```
Flutter App
 │
 ├── UI（カレンダーベースの入力・閲覧）
 │
 ├── SQLite
 │    ├── User
 │    ├── BodyMeasurement
 │    ├── Meal
 │    ├── Workout → WorkoutExercise → WorkoutSet
 │    └── AIAnalysis
 │
 ├── Statistics / Data Processing（期間ごとの統計計算はアプリ側で事前処理）
 │
 └── LLMService
      └── OpenAIService（V1で実装）
           ↑
     ユーザーが自分のAPI Keyを登録（BYOK）
     KeyはSecure Storageに保存、SQLiteには保存しない
```

- **サーバーなし。** ユーザーが自身のLLM API Keyを登録して使うBYOK（Bring Your Own Key）構造のため、開発者がAPI費用やサーバー運用を負担する必要がありません。
- `LLMService`インターフェースでProviderを抽象化しつつ、V1で実際に実装するProviderは**OpenAIのみ**に限定します。構造上の拡張性は確保しつつ、実装範囲はコントロールする方針です。

#### 今後の拡張方向

```
LLMService
 ├── OpenAIService   (V1)
 ├── GeminiService   (拡張)
 └── ClaudeService   (拡張)
```

複数LLMの並列分析、Providerごとの役割分担、結果比較などはV1のスコープから明確に除外し、以降の拡張機能とします。公開サービス化する場合や、API Keyをクライアントに直接持たせない構造が必要になった場合は、FastAPIベースのStateless Proxy導入も選択肢として残しておきます。

```
（今後の選択的拡張）
Flutter → FastAPI Proxy → LLM Provider
```

### データフロー

```
SQLite 元データ
      ↓
期間選択（直近7日 / 14日 / 30日 / カスタム）
      ↓
Flutterで統計計算（変化量、平均など）
      ↓
Structured Input Summary（JSON）
      ↓
LLM API
      ↓
自然言語による分析結果
      ↓
AIAnalysis 保存（input_summary + analysis_result）
      ↓
UI表示
```

計算可能な数値はアプリ側で先に計算し、LLMはパターンの解釈と自然言語でのフィードバックに集中させます。

### AIフィードバックの範囲

- 期間の総評
- 食事分析（平均摂取量、タンパク質摂取パターン、食事頻度、目標との適合性）
- 運動分析（頻度、筋力/有酸素の比率、運動量の変化、部位の偏り）
- 身体変化（体重/体脂肪率/骨格筋量の推移）
- 今後の方向性の提案

### データ保存とバックアップ

**Local-first。** すべての元データは端末内のSQLiteに保存されます。

- **バックアップ/復元**: `.db`ファイル自体をバックアップ単位とします。別フォーマットへの変換なしに、SQLite DBファイルをそのままバックアップ/復元します。
- **Export**: CSV/JSONは基本のバックアップ方式ではなく、ユーザーがデータを確認したり他のプログラムで活用したりするための補助機能として扱います。
- **Schema Migration**: アプリの最初のバージョンから`schema_version`を管理し、アプリのアップデート後も既存ユーザーの`.db`ファイルが正常に維持されるようにします。

### DBスキーマ（概要）

```
User
BodyMeasurement
Meal
Workout
  └── WorkoutExercise (strength / cardio)
        └── WorkoutSet (strength専用)
AIAnalysis (input_summaryを含む — 再現/デバッグ/比較用)
```

- 運動データは`Workout → WorkoutExercise → WorkoutSet`の3段構造に分離し、セットごとの記録（重量 × 回数）を自然に保存できるようにします。
- CardioはV1では別テーブルを作らず、`WorkoutExercise`のnullableフィールド（duration/distance/speed）として扱います。

スキーマ全体の定義は `/docs/schema.sql` を参照。*(今後追加予定)*

### 技術スタック

| 領域 | 選定 |
|---|---|
| App | Flutter |
| Local DB | SQLite |
| LLM (V1) | OpenAI API (BYOK) |
| API Key 保存 | Secure Storage (Android/iOS) |
| Server | なし (V1) |

### 開発ロードマップ

- [ ] **Phase 1 — 設計**: 要件整理、画面構成、DBスキーマ、LLMインターフェース設計
- [ ] **Phase 2 — Local MVP**: Flutter + SQLite、初期設定、カレンダー、食事/運動/身体記録、Migration構造
- [ ] **Phase 3 — LLM Integration**: LLMServiceインターフェース、OpenAIService、期間別統計 → AI分析
- [ ] **Phase 4 — Data Management**: `.db`バックアップ/復元、CSV/JSON Export、データ検証
- [ ] **Phase 5 — 高度化**: データ可視化、長期トレンド、AI分析履歴の比較、追加LLM Provider（Gemini/Claude）、複数LLM並列分析、結果比較、食品DB/API連携、LLM-assisted食事入力

### 未確定事項

- [ ] SQLiteライブラリの選定（sqfliteなど）
- [ ] OpenAIモデルの選定およびPrompt構造
- [ ] AIAnalysis結果の保存フォーマット（原文TEXT vs 構造化JSON）
- [ ] 体重/体脂肪率/骨格筋量のグラフUI
- [ ] 安全な`.db`バックアップ方式（復元時の既存データ上書き防止手順）

---

## English

### Overview

FitMind is a personalized fitness management app that stores a user's workout, diet, and body data long-term on the device's local database, and sends data from a chosen time period to an LLM to analyze trends and patterns.

Rather than simply asking an LLM questions about exercise or diet, the goal is the following flow:

```
Continuous accumulation of user data
        ↓
Structured data analysis
        ↓
Interpretation and feedback via LLM
```

### Core Design Philosophy

**Don't use the LLM as "memory."**

Even if the LLM doesn't remember previous conversations, the user's historical data must not disappear — all raw data is accumulated in a local SQLite database on the device. The LLM is used only as an **analysis engine**, not as persistent storage.

```
Persistent User Data → Structured Data Processing → LLM Analysis → Actionable Feedback
```

### Architecture

#### V1 (Local MVP + Single LLM Provider)

```
Flutter App
 │
 ├── UI (calendar-based input/viewing)
 │
 ├── SQLite
 │    ├── User
 │    ├── BodyMeasurement
 │    ├── Meal
 │    ├── Workout → WorkoutExercise → WorkoutSet
 │    └── AIAnalysis
 │
 ├── Statistics / Data Processing (period-based stats pre-computed in-app)
 │
 └── LLMService
      └── OpenAIService (implemented in V1)
           ↑
     User registers their own API Key (BYOK)
     Key stored in Secure Storage, never in SQLite
```

- **No server.** Uses a BYOK (Bring Your Own Key) structure where the user registers their own LLM API key, so the developer doesn't need to cover API costs or run a server.
- The `LLMService` interface abstracts the provider, but V1 implements **only OpenAI**. This keeps the architecture extensible while keeping the implementation scope controlled.

#### Future Expansion

```
LLMService
 ├── OpenAIService   (V1)
 ├── GeminiService   (future)
 └── ClaudeService   (future)
```

Parallel multi-LLM analysis, per-provider role assignment, and result comparison are explicitly excluded from V1 scope and left as future extensions. If the app later moves toward public deployment, or a structure where the API key isn't stored directly on the client becomes necessary, a FastAPI-based stateless proxy remains an option.

```
(optional future expansion)
Flutter → FastAPI Proxy → LLM Provider
```

### Data Flow

```
Raw data in SQLite
      ↓
Period selection (last 7 / 14 / 30 days / custom)
      ↓
Statistics computed in Flutter (deltas, averages, etc.)
      ↓
Structured Input Summary (JSON)
      ↓
LLM API
      ↓
Natural-language analysis
      ↓
Saved to AIAnalysis (input_summary + analysis_result)
      ↓
Displayed in UI
```

Anything that can be computed numerically is computed in-app first, so the LLM can focus on pattern interpretation and natural-language feedback.

### Scope of AI Feedback

- Period summary
- Diet analysis (average intake, protein pattern, meal frequency, alignment with goals)
- Exercise analysis (frequency, strength/cardio ratio, volume changes, body-part imbalance)
- Body composition changes (weight/body fat/skeletal muscle trends)
- Recommendations going forward

### Data Storage & Backup

**Local-first.** All raw data is stored in SQLite on the device.

- **Backup/Restore**: The `.db` file itself is the backup unit — the SQLite file is backed up and restored as-is, with no separate format conversion.
- **Export**: CSV/JSON are not the primary backup method; they're a supplementary feature for users to inspect data or use it in other programs.
- **Schema Migration**: `schema_version` is managed from the very first release so that existing users' `.db` files remain valid across app updates.

### DB Schema (Summary)

```
User
BodyMeasurement
Meal
Workout
  └── WorkoutExercise (strength / cardio)
        └── WorkoutSet (strength only)
AIAnalysis (includes input_summary — for reproducibility/debugging/comparison)
```

- Workout data is split into a three-level `Workout → WorkoutExercise → WorkoutSet` structure to naturally support set-level records (weight × reps).
- In V1, cardio has no separate table and instead uses nullable fields (duration/distance/speed) on `WorkoutExercise`.

Full schema definition: see `/docs/schema.sql`. *(to be added)*

### Tech Stack

| Area | Choice |
|---|---|
| App | Flutter |
| Local DB | SQLite |
| LLM (V1) | OpenAI API (BYOK) |
| API Key storage | Secure Storage (Android/iOS) |
| Server | None (V1) |

### Roadmap

- [ ] **Phase 1 — Design**: requirements, screen flow, DB schema, LLM interface design
- [ ] **Phase 2 — Local MVP**: Flutter + SQLite, onboarding, calendar, meal/workout/body logging, migration structure
- [ ] **Phase 3 — LLM Integration**: LLMService interface, OpenAIService, period stats → AI analysis
- [ ] **Phase 4 — Data Management**: `.db` backup/restore, CSV/JSON export, data validation
- [ ] **Phase 5 — Enhancements**: data visualization, long-term trends, comparing past AI analyses, additional LLM providers (Gemini/Claude), parallel multi-LLM analysis, result comparison, food DB/API integration, LLM-assisted meal entry

### Open Questions

- [ ] SQLite library choice (e.g. sqflite)
- [ ] OpenAI model selection and prompt design
- [ ] AIAnalysis result storage format (raw TEXT vs structured JSON)
- [ ] Weight/body fat/skeletal muscle chart UI
- [ ] Safe `.db` backup approach (preventing accidental overwrite on restore)

---

*This document summarizes the project's initial design discussion and will be updated as development progresses. / 本ドキュメントはプロジェクト初期設計の議論をまとめたものであり、開発の進行に伴い更新されます. / 이 문서는 프로젝트 초기 설계 논의를 정리한 초안이며 개발 진행에 따라 갱신됩니다.*
# PersonalFitnessAI
LLM 기반 맞춤형 운동·식단 관리 앱, LLMを活用したパーソナライズドな運動・食事管理アプリ, LLM-powered personalized fitness &amp; nutrition tracker

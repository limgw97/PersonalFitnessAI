# FitMind 설계 결정사항 (V1 확정본)

> 초기 기획서 + Claude/GPT 설계 리뷰 논의를 정리한 문서입니다.
> 논의 중간 버전(3개 LLM Provider 동시 지원 등)은 **폐기**되었으며, 아래 내용이 최종 기준입니다.

---

## 1. 핵심 원칙

- **Local-first**: 모든 원본 데이터는 기기 내 SQLite에 누적 저장
- **LLM = 분석 엔진**: 기억장치로 쓰지 않음
- **앱이 먼저 계산, LLM은 해석**: 평균/변화량 등 수치는 앱에서 계산하고 LLM은 패턴 해석과 자연어 피드백만 담당
- **스코프 통제**: "무엇을 넣을까"보다 "V1에서 무엇을 안 넣을까"를 우선 판단

```
Persistent User Data → Structured Data Processing → LLM Analysis → Actionable Feedback
```

---

## 2. V1 스코프 (최종)

| 항목 | V1 |
|---|---|
| Flutter + SQLite | ✅ |
| BYOK (사용자 직접 API Key 등록) | ✅ |
| API Key는 Secure Storage 저장 (SQLite 평문 저장 금지) | ✅ |
| `LLMService` 인터페이스 | ✅ |
| 실제 구현 Provider | **OpenAI 1개** |
| Provider 선택 UI | 구조만 확장 가능하게, 노출 옵션은 1개 |
| Gemini / Claude Provider 구현 | ❌ (Phase 5) |
| 복수 LLM 병렬 분석 / 역할 분배 / 결과 비교 | ❌ (Phase 5) |
| FastAPI Proxy | ❌ (향후 선택적 확장) |
| 음식 DB/API 연동, LLM 영양정보 추정 | ❌ (Phase 5) |

```
Flutter → SQLite → Statistics → LLMService → OpenAIService → OpenAI API
```

### 결정 이력

- **FastAPI Proxy → 제외**: 초기 리뷰에서는 API Key 보호용으로 제안되었으나, 최초 기획이 "사용자가 자기 API Key를 직접 연결"하는 BYOK 구조였으므로 서버 운영/비용 부담이 불필요. 공개 서비스화 시 재검토.
- **3개 Provider 동시 지원 → 축소**: OpenAI/Gemini/Claude는 요청 포맷, 스트리밍, 에러/레이트리밋 정책이 모두 달라 첫 앱 범위로 과다. 인터페이스만 설계하고 구현은 1개로 제한.
- **OpenAI 선택 이유**: LLM 연동 자체를 배우는 것이 목적이며, 하나를 확실히 구현한 뒤 나머지는 어댑터 추가 문제로 분리 가능.

---

## 3. 식단 입력 (V1)

- 음식명 자유 텍스트 + 칼로리/단백질 직접 입력 (탄수화물/지방은 선택)
- LLM의 영양정보 추정은 코어 로직에 넣지 않음 → 부정확한 추정값이 장기 분석 데이터의 신뢰도를 해칠 수 있음
- 기록 마찰이 가장 큰 이탈 요인이므로, 입력 UX는 최대한 단순하게 유지

---

## 4. 운동 데이터 구조

```
Workout → WorkoutExercise → WorkoutSet
```

- 근력운동은 세트별 기록(무게 × 반복)을 위해 3단 구조
- Cardio는 V1에서 별도 테이블 없이 `WorkoutExercise`의 nullable 필드(`duration_min`, `distance_km`, `avg_speed`)로 처리
- 인터벌 트레이닝 등 구간 기록이 필요해지면 그때 분리
- `exercise_type`과 필드 정합성(strength인데 cardio 필드가 채워진 경우 등)은 **Flutter Repository 레이어에서 검증**

---

## 5. DB Migration

- 스키마 버전은 별도 테이블 대신 SQLite 파일 헤더의 `PRAGMA user_version`으로 관리 (sqflite `version` 옵션)
  - 처음엔 `schema_version` 테이블로 계획했으나, sqflite가 같은 역할을 기본 제공하므로 변경
  - 버전이 `.db` 파일 헤더에 들어 있어 백업/복원 시 함께 이동
- 앱 시작 시 현재 버전 → 최신 버전까지 마이그레이션을 순차 실행 (sqflite가 트랜잭션으로 감쌈, 실패 시 전체 롤백)
- 더 새 버전 앱의 백업을 구버전 앱에서 열면 명확한 오류로 실패 (데이터 손상 방지)
- 연결 시 `PRAGMA foreign_keys = ON;` 필수 (미설정 시 `ON DELETE CASCADE`가 조용히 동작하지 않음)
- 기존 마이그레이션은 절대 수정하지 않고, 변경은 항상 새 버전으로 추가

```
lib/data/db/
  ├── app_database.dart   # DB 열기, FK 설정, 마이그레이션 연결
  ├── migrations.dart     # 버전별 마이그레이션 목록 + 실행기
  └── schema_v1.dart      # v1 CREATE 문 (docs/schema.sql과 동일)
```

전체 스키마는 [`schema.sql`](./schema.sql) 참고.

### 데이터 계층 구조

```
lib/
├── core/db_date.dart          # 'YYYY-MM-DD' ↔ DateTime
├── data/
│   ├── db/                    # DB 열기, 마이그레이션, 스키마
│   ├── models/                # UserProfile, BodyMeasurement, Meal, Workout(+Exercise, Set)
│   └── repositories/          # 테이블별 저장/조회 (화면은 Repository만 사용)
└── domain/period_summary.dart # 기간 통계 → LLM input_summary
```

- 입력값 검증(strength/cardio 규칙 포함)은 모델의 `validate()`에서, 저장 직전 Repository가 호출
- upsert는 `INSERT ... ON CONFLICT`(SQLite 3.24+) 대신 UPDATE → INSERT 순서 (구형 Android 기기 호환)
- 운동 세션 수정 시 종목/세트는 전부 지우고 다시 저장 (V1 단순화)
- 식단 평균은 "기록한 날" 기준, 탄수화물/지방은 기간 내 모든 식사에 값이 있을 때만 평균

---

## 6. AIAnalysis / input_summary

LLM에 실제로 전달한 구조화 데이터를 `input_summary`(JSON)로 함께 저장합니다. 결과 재현, 디버깅, 과거 분석과 현재 비교에 사용합니다.

```json
{
  "period": "2026-09-01/2026-09-07",
  "weight": { "start": 65.1, "end": 64.3, "change": -0.8 },
  "diet": { "avg_calories": 1850, "avg_protein": 118 },
  "exercise": { "strength_days": 3, "cardio_days": 2 }
}
```

`analysis_result`는 V1에서 원문 TEXT로 저장하고, 섹션별 구조화(JSON)는 실제 프롬프트 결과를 본 뒤 v2 마이그레이션으로 결정합니다.

---

## 7. 백업 / Export

- 기본 백업 단위: SQLite `.db` 파일 자체 (별도 포맷 변환 없음)
- 복원: Android 시스템 파일 선택기 우선 검토, 복원 전 현재 데이터 자동 백업 또는 확인 절차
- CSV/JSON은 백업이 아닌 보조 Export 기능 (Phase 4)

---

## 8. 개발 로드맵

| Phase | 내용 |
|---|---|
| 1 설계 | 요구사항, 화면 구성, DB 스키마, LLMService 인터페이스 |
| 2 Local MVP | Flutter, SQLite, 온보딩, 캘린더, 식단/신체/운동 기록, Migration |
| 3 LLM Integration | LLMService, OpenAIService, 기간별 통계 → AI 분석 → AIAnalysis 저장 |
| 4 Data Management | `.db` 백업/복원, CSV/JSON Export, 데이터 검증 |
| 5 고도화 | 차트, 장기 추세, AI 분석 이력 비교, Gemini/Claude Provider, 병렬 분석/결과 비교/역할 분배, 식품 DB/API, LLM-assisted 식단 입력 |

**V1 개발 원칙: LLM부터 만들지 않는다.** Flutter → SQLite → 입력 → 캘린더 → 조회 → 기간별 통계까지 완성한 뒤 LLM 계층을 붙입니다.

---

## 9. 미확정 사항

- [ ] SQLite 라이브러리 (sqflite 등)
- [ ] OpenAI 모델 선택 및 Prompt 구조
- [ ] AI에게 전달할 데이터 범위
- [ ] 체중/체지방/골격근 그래프 UI
- [ ] 안전한 `.db` 백업 방식 (SQLite Backup API 등)
- [ ] 향후 서버/클라우드 동기화 여부

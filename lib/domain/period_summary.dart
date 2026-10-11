import '../core/db_date.dart';
import '../data/models/body_measurement.dart';
import '../data/models/enums.dart';
import '../data/models/meal.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout.dart';
import '../data/repositories/body_measurement_repository.dart';
import '../data/repositories/meal_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/workout_repository.dart';

/// 기간 데이터를 LLM에 보낼 요약(input_summary)으로 만듭니다.
///
/// 원칙: 계산할 수 있는 숫자는 전부 앱에서 계산하고, LLM은 해석만 합니다.
/// 결과는 JSON으로 변환 가능한 Map이며, AIAnalysis.input_summary에 그대로 저장됩니다.
///
/// 평균값의 기준에 주의:
/// - 식단 평균은 "기간 전체 일수"가 아니라 "식사를 기록한 날" 기준입니다.
///   (기록을 빼먹은 날이 0kcal로 계산되면 평균이 실제보다 크게 낮아지기 때문)
///   그래서 기록 일수(logged_days)를 함께 보내 LLM이 기록 충실도를 판단하게 합니다.
/// - 탄수화물/지방은 선택 입력이라, 기간 내 모든 식사에 값이 있을 때만 평균을 냅니다.
///   일부만 입력된 상태로 평균을 내면 실제보다 낮게 보이기 때문입니다.
Map<String, Object?> buildPeriodSummary({
  required DateTime start,
  required DateTime end,
  required UserProfile? user,
  required List<BodyMeasurement> measurements,
  required List<Meal> meals,
  required List<Workout> workouts,
}) {
  final from = dateOnly(start);
  final to = dateOnly(end);
  if (to.isBefore(from)) {
    throw ArgumentError('기간의 끝이 시작보다 빠릅니다.');
  }

  bool inPeriod(DateTime d) {
    final day = dateOnly(d);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  final periodMeasurements = measurements.where((m) => inPeriod(m.date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final periodMeals = meals.where((m) => inPeriod(m.date)).toList();
  final periodWorkouts = workouts.where((w) => inPeriod(w.date)).toList();

  // 단백질 체중당 섭취량 계산용: 기간 내 마지막 체중, 없으면 초기 체중
  final referenceWeight = periodMeasurements.isNotEmpty
      ? periodMeasurements.last.weight
      : user?.initialWeight;

  return {
    'period': {
      'start': toDbDate(from),
      'end': toDbDate(to),
      'days': daysInclusive(from, to),
    },
    'user': user == null
        ? null
        : {
            'goal': user.goal.dbValue,
            'gender': user.gender.dbValue,
            'age': user.age,
            'height_cm': user.height,
          },
    'body': _bodySummary(periodMeasurements),
    'diet': _dietSummary(periodMeals, referenceWeight),
    'exercise': _exerciseSummary(periodWorkouts),
  };
}

Map<String, Object?> _bodySummary(List<BodyMeasurement> sorted) {
  return {
    'measurement_days': sorted.length,
    'weight_kg': _trend(sorted.map((m) => m.weight).toList()),
    'body_fat_pct': _trend(
      sorted.map((m) => m.bodyFat).whereType<double>().toList(),
    ),
    'skeletal_muscle_kg': _trend(
      sorted.map((m) => m.skeletalMuscle).whereType<double>().toList(),
    ),
  };
}

/// 날짜순 값 목록 → 시작/끝/변화량. 값이 없으면 null, 하나뿐이면 change는 null.
Map<String, Object?>? _trend(List<double> values) {
  if (values.isEmpty) return null;
  return {
    'start': values.first,
    'end': values.last,
    'change': values.length < 2 ? null : _round(values.last - values.first, 1),
    'records': values.length,
  };
}

Map<String, Object?> _dietSummary(List<Meal> meals, double? referenceWeight) {
  final loggedDays = meals.map((m) => toDbDate(m.date)).toSet().length;
  if (loggedDays == 0) {
    return {
      'logged_days': 0,
      'meals': 0,
      'avg_meals_per_logged_day': null,
      'avg_calories_kcal': null,
      'avg_protein_g': null,
      'avg_carbohydrate_g': null,
      'avg_fat_g': null,
      'protein_g_per_kg': null,
    };
  }

  double? avgIfAll(double? Function(Meal) pick) {
    final values = meals.map(pick).toList();
    if (values.any((v) => v == null)) return null;
    return _round(_sum(values.whereType<double>()) / loggedDays, 1);
  }

  final avgProtein = _sum(meals.map((m) => m.protein)) / loggedDays;

  return {
    'logged_days': loggedDays,
    'meals': meals.length,
    'avg_meals_per_logged_day': _round(meals.length / loggedDays, 1),
    'avg_calories_kcal': _round(_sum(meals.map((m) => m.calories)) / loggedDays, 1),
    'avg_protein_g': _round(avgProtein, 1),
    'avg_carbohydrate_g': avgIfAll((m) => m.carbohydrate),
    'avg_fat_g': avgIfAll((m) => m.fat),
    'protein_g_per_kg': (referenceWeight == null || referenceWeight <= 0)
        ? null
        : _round(avgProtein / referenceWeight, 2),
  };
}

Map<String, Object?> _exerciseSummary(List<Workout> workouts) {
  Set<String> daysWhere(bool Function(Workout) test) =>
      workouts.where(test).map((w) => toDbDate(w.date)).toSet();

  final allExercises = [for (final w in workouts) ...w.exercises];
  final strength =
      allExercises.where((e) => e.type == ExerciseType.strength).toList();
  final cardio =
      allExercises.where((e) => e.type == ExerciseType.cardio).toList();

  return {
    'sessions': workouts.length,
    'workout_days': daysWhere((_) => true).length,
    'strength_days': daysWhere((w) => w.hasStrength).length,
    'cardio_days': daysWhere((w) => w.hasCardio).length,
    'strength': {
      'total_sets': strength.fold<int>(0, (sum, e) => sum + e.sets.length),
      'total_volume_kg': _round(_sum(strength.map((e) => e.volume)), 1),
      'by_exercise': _strengthByExercise(workouts),
    },
    'cardio': {
      'total_minutes':
          _round(_sum(cardio.map((e) => e.durationMin).whereType<double>()), 1),
      'total_distance_km':
          _round(_sum(cardio.map((e) => e.distanceKm).whereType<double>()), 2),
      'by_exercise': _cardioByExercise(workouts),
    },
  };
}

/// 종목별 집계 (근력). 이름은 대소문자/앞뒤 공백을 무시하고 같은 종목으로 묶습니다.
List<Map<String, Object?>> _strengthByExercise(List<Workout> workouts) {
  final groups = <String, _ExerciseGroup>{};
  for (final w in workouts) {
    for (final e in w.exercises.where((x) => x.type == ExerciseType.strength)) {
      final group = groups.putIfAbsent(_key(e.name), () => _ExerciseGroup(e.name.trim()));
      group.days.add(toDbDate(w.date));
      group.sets += e.sets.length;
      group.volume += e.volume;
      for (final s in e.sets) {
        if (s.weight > group.maxWeight) group.maxWeight = s.weight;
      }
    }
  }
  return _sortGroups(groups.values)
      .map((g) => {
            'name': g.name,
            'days': g.days.length,
            'sets': g.sets,
            'max_weight_kg': g.maxWeight,
            'volume_kg': _round(g.volume, 1),
          })
      .toList();
}

/// 종목별 집계 (유산소).
List<Map<String, Object?>> _cardioByExercise(List<Workout> workouts) {
  final groups = <String, _ExerciseGroup>{};
  for (final w in workouts) {
    for (final e in w.exercises.where((x) => x.type == ExerciseType.cardio)) {
      final group = groups.putIfAbsent(_key(e.name), () => _ExerciseGroup(e.name.trim()));
      group.days.add(toDbDate(w.date));
      group.minutes += e.durationMin ?? 0;
      group.distance += e.distanceKm ?? 0;
    }
  }
  return _sortGroups(groups.values)
      .map((g) => {
            'name': g.name,
            'days': g.days.length,
            'minutes': _round(g.minutes, 1),
            'distance_km': _round(g.distance, 2),
          })
      .toList();
}

/// 자주 한 종목(일수 많은 순) → 이름순.
List<_ExerciseGroup> _sortGroups(Iterable<_ExerciseGroup> groups) =>
    groups.toList()
      ..sort((a, b) {
        final byDays = b.days.length.compareTo(a.days.length);
        return byDays != 0 ? byDays : a.name.compareTo(b.name);
      });

class _ExerciseGroup {
  _ExerciseGroup(this.name);

  /// 처음 등장한 표기를 그대로 사용
  final String name;
  final Set<String> days = {};
  int sets = 0;
  double volume = 0;
  double maxWeight = 0;
  double minutes = 0;
  double distance = 0;
}

String _key(String name) => name.trim().toLowerCase();

double _sum(Iterable<double> values) =>
    values.fold<double>(0, (sum, v) => sum + v);

double _round(double value, int digits) {
  var factor = 1.0;
  for (var i = 0; i < digits; i++) {
    factor *= 10;
  }
  return (value * factor).roundToDouble() / factor;
}

/// DB에서 기간 데이터를 읽어 [buildPeriodSummary]를 실행합니다.
class PeriodSummaryService {
  PeriodSummaryService({
    required this.users,
    required this.measurements,
    required this.meals,
    required this.workouts,
  });

  final UserRepository users;
  final BodyMeasurementRepository measurements;
  final MealRepository meals;
  final WorkoutRepository workouts;

  Future<Map<String, Object?>> summarize(DateTime start, DateTime end) async {
    return buildPeriodSummary(
      start: start,
      end: end,
      user: await users.get(),
      measurements: await measurements.getRange(start, end),
      meals: await meals.getRange(start, end),
      workouts: await workouts.getRange(start, end),
    );
  }
}

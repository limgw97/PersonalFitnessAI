import '../../core/db_date.dart';
import 'enums.dart';
import 'map_utils.dart';

/// 한 끼 식사 기록. 음식은 자유 텍스트, 영양정보는 사용자가 직접 입력합니다.
class Meal {
  const Meal({
    this.id,
    required this.date,
    required this.mealType,
    required this.foodText,
    required this.calories,
    required this.protein,
    this.carbohydrate,
    this.fat,
  });

  final int? id;
  final DateTime date;
  final MealType mealType;

  /// 예: "닭가슴살 150g, 밥 한 공기"
  final String foodText;

  /// kcal
  final double calories;

  /// g
  final double protein;

  /// g (선택)
  final double? carbohydrate;

  /// g (선택)
  final double? fat;

  factory Meal.fromMap(Map<String, Object?> map) => Meal(
        id: readIntOrNull(map, 'id'),
        date: fromDbDate(map['date'] as String),
        mealType: MealType.fromDb(map['meal_type'] as String),
        foodText: map['food_text'] as String,
        calories: readDouble(map, 'calories'),
        protein: readDouble(map, 'protein'),
        carbohydrate: readDoubleOrNull(map, 'carbohydrate'),
        fat: readDoubleOrNull(map, 'fat'),
      );

  Map<String, Object?> toMap() => {
        'date': toDbDate(date),
        'meal_type': mealType.dbValue,
        'food_text': foodText,
        'calories': calories,
        'protein': protein,
        'carbohydrate': carbohydrate,
        'fat': fat,
      };

  /// 입력값 검증. 문제가 있으면 [ArgumentError]를 던집니다.
  void validate() {
    if (foodText.trim().isEmpty) {
      throw ArgumentError('음식 내용을 입력하세요.');
    }
    if (calories < 0 || protein < 0) {
      throw ArgumentError('칼로리와 단백질은 0 이상이어야 합니다.');
    }
    if ((carbohydrate ?? 0) < 0 || (fat ?? 0) < 0) {
      throw ArgumentError('탄수화물과 지방은 0 이상이어야 합니다.');
    }
  }
}

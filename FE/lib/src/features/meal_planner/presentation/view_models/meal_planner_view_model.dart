import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/meal_entities.dart';
import '../../domain/repositories/meal_plan_repository.dart';

class MealPlannerViewModel extends ViewModel {
  MealPlannerViewModel(
    this._repository,
    this._auth, {
    DateTime? today,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => today ?? DateTime.now()) {
    _weekStart = _currentWeek();
    _plan = _repository.generate(
      weekStart: _weekStart,
      generation: 0,
      ingredients: [],
    );
    _updateShopping();
    _auth.addListener(_resetActor);
  }
  final MealPlanRepository _repository;
  final AuthViewModel _auth;
  final DateTime Function() _clock;
  late DateTime _weekStart;
  late WeeklyMealPlan _plan;
  int _selectedDay = 0;
  int _request = 0;
  String _height = '', _weight = '', _pantry = '';
  bool _adult = false;
  MeasurementUnit _unit = MeasurementUnit.metric;
  BmiProfile? _profile;
  String? _bmiError;
  List<IngredientItem> _shopping = [];
  List<String> _available = [];
  WeeklyMealPlan get plan => _plan;
  MealDay get selectedDay => _plan.days[_selectedDay];
  int get selectedIndex => _selectedDay;
  BmiProfile? get profile => _profile;
  String? get bmiError => _bmiError;
  MeasurementUnit get unit => _unit;
  bool get adult => _adult;
  String get height => _height;
  String get weight => _weight;
  String get pantry => _pantry;
  List<IngredientItem> get shopping => List.unmodifiable(_shopping);
  List<String> get available => List.unmodifiable(_available);
  String get dateRange =>
      '${_weekStart.day} ${_months[_weekStart.month - 1]} – ${_plan.days.last.date.day} ${_months[_plan.days.last.date.month - 1]}, ${_weekStart.year}';
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  DateTime _currentWeek() {
    final date = _clock();
    return DateTime(date.year, date.month, date.day - date.weekday + 1);
  }

  void syncCurrentWeek() {
    if (disposed) return;
    final week = _currentWeek();
    if (week == _weekStart) return;
    _request++;
    try {
      final plan = _repository.generate(
        weekStart: week,
        generation: 0,
        ingredients: _available,
      );
      _weekStart = week;
      _plan = plan;
      _selectedDay = 0;
      _updateShopping();
      clearError();
    } catch (_) {
      fail('Could not generate the demo plan. Please retry.');
    }
  }

  void selectDay(int index) {
    if (index >= 0 && index < 7) {
      _selectedDay = index;
      emit();
    }
  }

  void _clearBmiResult() {
    _profile = null;
    _bmiError = null;
    emit();
  }

  void setHeight(String value) {
    _height = value;
    _clearBmiResult();
  }

  void setWeight(String value) {
    _weight = value;
    _clearBmiResult();
  }

  void setPantry(String value) {
    _pantry = value;
  }

  void setAdult(bool value) {
    _adult = value;
    _clearBmiResult();
  }

  void setUnit(MeasurementUnit value) {
    if (value == _unit) return;
    _unit = value;
    _height = '';
    _weight = '';
    _clearBmiResult();
  }

  bool _failBmi(String message) {
    _profile = null;
    _bmiError = message;
    emit();
    return false;
  }

  bool calculateBmi() {
    if (!_auth.canParticipate) {
      return _failBmi('Sign in before using the calculator.');
    }
    if (!_adult) {
      return _failBmi(
        'This reference calculator is for adults aged 20 and older only.',
      );
    }
    final height = double.tryParse(_height.trim());
    final weight = double.tryParse(_weight.trim());
    if (height == null ||
        weight == null ||
        !height.isFinite ||
        !weight.isFinite) {
      return _failBmi('Enter valid numeric height and weight.');
    }
    final cm = _unit == MeasurementUnit.metric ? height : height * 2.54;
    final kg = _unit == MeasurementUnit.metric ? weight : weight * .45359237;
    if (cm < 50 || cm > 260 || kg < 15 || kg > 500) {
      return _failBmi(
        'Check your units and enter realistic positive measurements.',
      );
    }
    _profile = BmiProfile(
      heightCm: cm,
      weightKg: kg,
      bmi: kg / ((cm / 100) * (cm / 100)),
    );
    _bmiError = null;
    emit();
    return true;
  }

  Future<void> generate() async {
    if (!_auth.canParticipate) {
      fail('Sign in to generate a meal plan.');
      return;
    }
    syncCurrentWeek();
    if (busy || disposed) return;
    final request = ++_request;
    final ingredients = _pantry
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    setBusy(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (disposed || request != _request || !_auth.canParticipate) return;
    try {
      final week = _currentWeek();
      final plan = _repository.generate(
        weekStart: week,
        generation: week == _weekStart ? _plan.generation + 1 : 1,
        ingredients: ingredients,
      );
      if (week != _weekStart) _selectedDay = 0;
      _weekStart = week;
      _plan = plan;
      _available = ingredients;
      _updateShopping();
      setBusy(false);
    } catch (_) {
      fail('Could not generate the demo plan. Please retry.');
    }
  }

  void toggleIngredient(String name) {
    if (!_auth.canParticipate) return;
    _shopping = [
      for (final item in _shopping) item.name == name ? item.toggle() : item,
    ];
    emit();
  }

  void _updateShopping() {
    final names =
        _plan.days
            .expand((d) => d.meals)
            .expand((m) => m.ingredients)
            .toSet()
            .toList()
          ..sort();
    _shopping = names
        .map(
          (name) => IngredientItem(
            name: name,
            checked: _available.any(
              (a) => a.toLowerCase() == name.toLowerCase(),
            ),
          ),
        )
        .toList();
  }

  void _resetActor() {
    _request++;
    _height = '';
    _weight = '';
    _pantry = '';
    _profile = null;
    _bmiError = null;
    _adult = false;
    _unit = MeasurementUnit.metric;
    _available = [];
    _selectedDay = 0;
    _weekStart = _currentWeek();
    _plan = _repository.generate(
      weekStart: _weekStart,
      generation: 0,
      ingredients: [],
    );
    _updateShopping();
    clearError();
  }

  @override
  void dispose() {
    _request++;
    _auth.removeListener(_resetActor);
    super.dispose();
  }
}

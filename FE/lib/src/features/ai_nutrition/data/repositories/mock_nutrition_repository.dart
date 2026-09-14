import '../../domain/entities/nutrition_entities.dart';
import '../../domain/repositories/nutrition_repository.dart';

class MockNutritionRepository implements NutritionRepository {
  MockNutritionRepository({this.tokenDelay = const Duration(milliseconds: 28)});
  final Duration tokenDelay;
  @override
  List<NutritionTip> get quickActions => const [
    NutritionTip('Plant protein', 'How can I get enough plant protein?'),
    NutritionTip('Easy food swaps', 'What are easy vegan food swaps?'),
    NutritionTip('Vitamin B12', 'What should I know about vitamin B12?'),
    NutritionTip('Dinner ideas', 'Give me a balanced vegan dinner idea.'),
  ];
  @override
  List<FoodSubstitution> get substitutions => const [
    FoodSubstitution(
      'Dairy milk',
      'Fortified soy milk',
      'Check calcium, vitamin D, B12, and protein on the label.',
    ),
    FoodSubstitution(
      'Minced meat',
      'Lentils or crumbled tofu',
      'Try in a tomato sauce with mushrooms.',
    ),
    FoodSubstitution(
      'Butter',
      'Olive oil',
      'Works for sautéing; baking ratios vary by recipe.',
    ),
  ];
  String _answer(String prompt) {
    final text = prompt.toLowerCase();
    if (text.contains('b12')) {
      return 'Vitamin B12 deserves a place in your plant-based routine.\n\nUnfortified plant foods are not a reliable B12 source. Look for fortified foods and discuss an appropriate supplement with a qualified clinician or dietitian.\n\nCheck labels: products and fortification amounts vary. If you have symptoms or concerns, seek individual assessment rather than relying on this demo.';
    }
    if (text.contains('swap') || text.contains('substitut')) {
      return 'Small swaps can make your usual meals plant-based.\n\n${substitutions.map((s) => '• ${s.original} → ${s.alternative}. ${s.note}').join('\n\n')}\n\nFor allergies, read the full ingredient list and cross-contact guidance.';
    }
    if (text.contains('protein')) {
      return 'Think variety, not perfection.\n\n• Add a protein-rich food to your meals: tofu, tempeh, beans, lentils, or edamame.\n• Include grains, vegetables, and a source of fat for satisfying meals.\n• Try a tofu and quinoa bowl with broccoli and a tahini-lemon dressing.\n\nProtein needs differ with age, activity, health, and other factors. A registered dietitian can help personalize them.';
    }
    if (text.contains('cure') ||
        text.contains('diagnos') ||
        text.contains('disease') ||
        text.contains('pregnan')) {
      return 'This demo cannot diagnose conditions or provide an individualized treatment plan. A clinician or registered dietitian can help you plan safely for your circumstances. For urgent symptoms, contact local emergency services.\n\nFor general meal inspiration, try a variety of legumes, grains, vegetables, fruit, nuts, and seeds that fit your needs.';
    }
    return 'Let’s keep dinner simple and satisfying.\n\nTry a chickpea bowl: cooked quinoa, roasted chickpeas, colorful vegetables, and a lemon-tahini sauce.\n\n1. Cook the quinoa according to the packet.\n2. Roast the chickpeas and vegetables until ready.\n3. Combine and finish with the sauce.\n\nUse the meal planner for more ideas. Check ingredients for allergies; this is a sample response, not a personalized nutrition prescription.';
  }

  @override
  Stream<String> streamResponse(String prompt) async* {
    if (prompt.trim() == '/demo-error') {
      await Future<void>.delayed(tokenDelay);
      throw StateError('Simulated connection issue. Try a different question.');
    }
    for (final word in _answer(prompt).split(' ')) {
      await Future<void>.delayed(tokenDelay);
      yield '$word ';
    }
  }
}

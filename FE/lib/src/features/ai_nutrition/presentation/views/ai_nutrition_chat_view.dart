import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/ai_nutrition_view_model.dart';
import '../widgets/nutrition_chat_panel.dart';

class AiNutritionChatView extends StatelessWidget {
  const AiNutritionChatView({super.key});
  @override
  Widget build(BuildContext context) =>
      NutritionChatPanel(vm: context.read<AiNutritionViewModel>());
}

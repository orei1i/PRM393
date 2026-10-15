// lib/features/meal_planner/presentation/controllers/pantry_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../scanner/domain/vegan_check.dart';
import '../../data/models/pantry_model.dart';
import '../../data/pantry_api_service.dart';
import '../../domain/entities/meal_plan.dart';

/// "Nguyên liệu trong tủ" (`user_ingredients`): vegan foods only. Rebuilt
/// per account through [pantryApiProvider].
final pantryControllerProvider =
    AsyncNotifierProvider<PantryController, List<PantryItem>>(
        PantryController.new);

class PantryController extends AsyncNotifier<List<PantryItem>> {
  PantryApiService get _api => ref.read(pantryApiProvider);

  @override
  Future<List<PantryItem>> build() async {
    final api = ref.watch(pantryApiProvider);
    return _entities(await api.getPantry());
  }

  static List<PantryItem> _entities(List<PantryItemDto> dtos) =>
      dtos.map((d) => d.toEntity()).toList();

  /// Waits for the first load so a later result can't overwrite a change.
  Future<void> _loaded() async {
    try {
      await future;
    } catch (_) {
      // The change below refreshes the list anyway.
    }
  }

  /// For the scanner ("Lưu vào tủ lạnh"): saves the confirmed vegan items;
  /// anything not vegan is skipped. Detected foods carry the scan time
  /// ("Quét"); typed-in names and swaps go without one ("Tự thêm"). Same
  /// names refresh the existing rows. Returns how many were sent; throws on
  /// failure.
  Future<int> addFromScan(List<ScannedPantryItem> items) async {
    final now = DateTime.now();
    final input = [
      for (final item in items)
        if (item.isVegan && item.name.trim().isNotEmpty)
          AddPantryItemDto(
            ingredient: item.name.trim(),
            scannedAt: item.source == PantrySource.scan ? now : null,
          ),
    ];
    if (input.isEmpty) return 0;
    await _loaded();
    state = AsyncData(_entities(await _api.addItems(input)));
    return input.length;
  }

  /// Typed in on the Thực đơn tab. A food that isn't vegan is refused (not
  /// sent): the returned verdict then carries the reason and vegan swaps for
  /// the UI. Throws on a save failure.
  Future<VeganVerdict> addManual(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const VeganVerdict.vegan();
    final verdict = classifyVegan(trimmed);
    if (!verdict.isVegan) return verdict;
    await _loaded();
    state = AsyncData(_entities(
        await _api.addItems([AddPantryItemDto(ingredient: trimmed)])));
    return verdict;
  }

  /// Optimistic; restores the item and rethrows on failure.
  Future<void> remove(PantryItem item) async {
    final before = state.valueOrNull ?? const <PantryItem>[];
    state = AsyncData(before.where((i) => i.id != item.id).toList());
    try {
      await _api.removeItem(item.id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> clear() async {
    final before = state.valueOrNull ?? const <PantryItem>[];
    state = const AsyncData(<PantryItem>[]);
    try {
      await _api.clear();
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }
}

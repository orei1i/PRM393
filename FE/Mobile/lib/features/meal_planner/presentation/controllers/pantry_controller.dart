// lib/features/meal_planner/presentation/controllers/pantry_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/text_search.dart';
import '../../../ingredient/data/ingredient_api_service.dart';
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

  /// Swiped-away items by id: where they were in the list and their pending
  /// delete, for "Hoàn tác".
  final _removed = <String, ({int index, Future<void> request})>{};

  @override
  Future<List<PantryItem>> build() async {
    final api = ref.watch(pantryApiProvider);
    return _entities(await api.getPantry());
  }

  static List<PantryItem> _entities(List<PantryItemDto> dtos) =>
      dtos.map((d) => d.toEntity()).toList();

  /// A name typed without accents ("ca chua") is saved as the nutrition DB
  /// spells it ("Cà chua"), when it is exactly that food. Anything else, or a
  /// failed lookup, keeps what was typed.
  Future<String> _catalogName(String name) async {
    final key = foldVietnamese(name);
    if (key != name.toLowerCase()) return name;
    try {
      final rows = await ref.read(ingredientApiProvider).search(name);
      for (final row in rows) {
        if (foldVietnamese(row.name) == key) return row.name;
      }
    } catch (_) {
      // Saving doesn't depend on the lookup.
    }
    return name;
  }

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
            ingredient: item.source == PantrySource.scan
                ? item.name.trim()
                : await _catalogName(item.name.trim()),
            scannedAt: item.source == PantrySource.scan ? now : null,
          ),
    ];
    if (input.isEmpty) return 0;
    await _loaded();
    state = AsyncData(_entities(await _api.addItems(input)));
    return input.length;
  }

  /// Typed in "Nguyên liệu trong tủ". A food that isn't vegan is refused (not
  /// sent): the returned verdict then carries the reason and vegan swaps for
  /// the UI. Throws on a save failure.
  Future<VeganVerdict> addManual(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const VeganVerdict.vegan();
    final verdict = classifyVegan(trimmed);
    if (!verdict.isVegan) return verdict;
    await _loaded();
    final ingredient = await _catalogName(trimmed);
    state = AsyncData(_entities(
        await _api.addItems([AddPantryItemDto(ingredient: ingredient)])));
    return verdict;
  }

  /// Optimistic; restores the item and rethrows on failure.
  Future<void> remove(PantryItem item) async {
    final before = state.valueOrNull ?? const <PantryItem>[];
    final index = before.indexWhere((i) => i.id == item.id);
    state = AsyncData(before.where((i) => i.id != item.id).toList());
    final request = _api.removeItem(item.id);
    _removed[item.id] = (index: index < 0 ? 0 : index, request: request);
    try {
      await request;
    } catch (_) {
      _removed.remove(item.id);
      state = AsyncData(before);
      rethrow;
    }
  }

  /// "Hoàn tác" after a swipe: saves [item] again with its scan time, so it
  /// keeps its "Quét" / "Tự thêm" source, back where it was in the list
  /// (not on top like a new item). Waits for the delete first, so a quick
  /// tap can't race it. Throws on failure.
  Future<void> restore(PantryItem item) async {
    final removed = _removed.remove(item.id);
    if (removed == null) {
      // The delete failed and the item is back already.
      if (state.valueOrNull?.any((i) => i.id == item.id) ?? false) return;
    } else {
      try {
        await removed.request;
      } catch (_) {
        return; // Same: the delete failed, nothing to restore.
      }
    }
    await _loaded();
    final index = removed?.index ?? 0;
    final list = _entities(await _api.restoreItem(
        AddPantryItemDto(
          ingredient: item.ingredient,
          scannedAt: item.scannedAt,
          quantity: item.quantity,
          unit: item.unit,
          expiryDate: item.expiryDate,
        ),
        index: index));
    state = AsyncData(_placed(list, item.ingredient, index));
  }

  /// [list] with the row named [name] at [index]: the API may list a
  /// restored row elsewhere (on top, as the newest).
  static List<PantryItem> _placed(
      List<PantryItem> list, String name, int index) {
    final key = foldVietnamese(name.trim());
    final at = list.indexWhere((p) => foldVietnamese(p.ingredient) == key);
    if (at < 0 || at == index) return list;
    final row = list.removeAt(at);
    return list..insert(index.clamp(0, list.length), row);
  }

  /// "Sửa số lượng & hạn dùng". Throws on failure (the sheet keeps the input).
  Future<void> updateItem(PantryItem item,
      {required double quantity,
      required String unit,
      DateTime? expiryDate}) async {
    final saved = (await _api.updateItem(
            item.id,
            UpdatePantryItemDto(
                quantity: quantity, unit: unit, expiryDate: expiryDate)))
        .toEntity();
    final list = state.valueOrNull ?? const <PantryItem>[];
    state = AsyncData([for (final i in list) i.id == saved.id ? saved : i]);
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

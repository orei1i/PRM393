// lib/features/scanner/presentation/controllers/scanner_controller.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../data/models/scan_result_model.dart';
import '../../data/scanner_api_service.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../../domain/vegan_check.dart';

enum ScanStatus { idle, analyzing, detected, empty, error }

enum MenuStatus { idle, generating, ready, error }

class ScannerState {
  const ScannerState({
    this.status = ScanStatus.idle,
    this.items = const [],
    this.errorMessage,
    this.menuStatus = MenuStatus.idle,
    this.menu = const [],
    this.menuError,
  });

  final ScanStatus status;
  final List<DetectedIngredient> items;
  final String? errorMessage;
  final MenuStatus menuStatus;
  final List<MenuSuggestion> menu;
  final String? menuError;

  /// "Gợi ý món" with nothing to cook from; gone once there is something.
  static const noSavableItems =
      'Hãy xác nhận hoặc thêm ít nhất 1 nguyên liệu thuần chay.';

  List<DetectedIngredient> get confirmedItems =>
      items.where((i) => i.confirmed).toList();

  /// Confirmed and vegan: what "Lưu vào tủ lạnh" saves and what dish ideas
  /// are built from. Non-vegan items are never saved.
  List<DetectedIngredient> get savableItems =>
      items.where((i) => i.savable).toList();
  List<DetectedIngredient> get veganItems =>
      items.where((i) => i.isVegan).toList();
  List<DetectedIngredient> get nonVeganItems =>
      items.where((i) => !i.isVegan).toList();
  int get pendingCount => items.where((i) => !i.confirmed).length;

  /// "7 thực phẩm · 5 thuần chay · 2 không thuần chay" (zero parts left out).
  String get summary {
    final vegan = veganItems.length;
    final nonVegan = items.length - vegan;
    return [
      '${items.length} thực phẩm',
      if (vegan > 0) '$vegan thuần chay',
      if (nonVegan > 0) '$nonVegan không thuần chay',
    ].join(' · ');
  }

  bool get isBusy =>
      status == ScanStatus.analyzing || menuStatus == MenuStatus.generating;

  ScannerState copyWith({
    ScanStatus? status,
    List<DetectedIngredient>? items,
    String? errorMessage,
    bool clearError = false,
    MenuStatus? menuStatus,
    List<MenuSuggestion>? menu,
    String? menuError,
    bool clearMenuError = false,
  }) {
    final nextItems = items ?? this.items;
    final nextError = clearMenuError ? null : (menuError ?? this.menuError);
    final answered =
        nextError == noSavableItems && nextItems.any((i) => i.savable);
    return ScannerState(
      status: status ?? this.status,
      items: nextItems,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      menuStatus: answered ? MenuStatus.idle : (menuStatus ?? this.menuStatus),
      menu: menu ?? this.menu,
      menuError: answered ? null : nextError,
    );
  }
}

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerState>(ScannerController.new);

class ScannerController extends Notifier<ScannerState> {
  ScannerApiService get _api => ref.read(scannerApiProvider);
  int _manualCounter = 0;

  @override
  ScannerState build() {
    // Signing out or switching account starts with an empty tray.
    ref.watch(plannerUserIdProvider);
    return const ScannerState();
  }

  /// Sends the frozen frame for detection. [jpegBytes] is empty in mock preview mode.
  Future<void> analyze(Uint8List jpegBytes) async {
    state = state.copyWith(status: ScanStatus.analyzing, clearError: true);
    try {
      final result = await _api.scanImage(jpegBytes);
      final detected = result.items.map((d) => d.toEntity()).toList();
      final merged = _merge(state.items, detected);
      state = state.copyWith(
        status: merged.isEmpty ? ScanStatus.empty : ScanStatus.detected,
        items: merged,
        menuStatus: MenuStatus.idle,
        menu: const [],
      );
    } catch (e) {
      state = state.copyWith(
          status: ScanStatus.error, errorMessage: describeError(e));
    }
  }

  /// Low-confidence item → user picked the right name. The item is then marked
  /// as verified by the user and keeps the score of the picked candidate
  /// (a name typed in "Loại khác…" counts as certain, like manual items).
  /// A new name is checked again for vegan (server flag of the candidate,
  /// else the local check).
  void confirm(String id, {String? name}) => _update(id, (i) {
        final picked = (name ?? i.name).trim();
        bool same(String other) => other.toLowerCase() == picked.toLowerCase();
        final score = same(i.name)
            ? i.confidence
            : i.alternatives
                    .where((a) => same(a.name))
                    .map((a) => a.confidence)
                    .firstOrNull ??
                1.0;
        return i.copyWith(
          name: picked,
          confidence: score,
          vegan: i.veganVerdictFor(picked),
          confirmed: true,
          userVerified: true,
        );
      });

  /// Returns the removed item and its index so the UI can offer Undo.
  (DetectedIngredient, int)? remove(String id) {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index < 0) return null;
    final removed = state.items[index];
    state = state.copyWith(items: [...state.items]..removeAt(index));
    return (removed, index);
  }

  void restore(DetectedIngredient item, int index) {
    final items = [...state.items];
    items.insert(index > items.length ? items.length : index, item);
    state = state.copyWith(items: items, status: ScanStatus.detected);
  }

  /// "Nhập tay" (or a "Gợi ý thay thế" chip). The name is checked for vegan
  /// locally, so it behaves the same offline. Returns the new item, or
  /// `null` for an empty name or one already in the tray.
  DetectedIngredient? addManual(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return null;
    final exists =
        state.items.any((i) => i.name.toLowerCase() == name.toLowerCase());
    if (exists) return null;
    _manualCounter++;
    final vegan = classifyVegan(name);
    final item = DetectedIngredient(
      id: 'manual_$_manualCounter',
      name: name,
      confidence: 1,
      isVegan: vegan.isVegan,
      nonVeganReason: vegan.nonVeganReason,
      veganAlternatives: vegan.veganAlternatives,
      manual: true,
    );
    state = state
        .copyWith(items: [...state.items, item], status: ScanStatus.detected);
    return item;
  }

  /// "Gợi ý món từ nguyên liệu này": vegan, confirmed items only.
  Future<void> generateMenu() async {
    final ingredients = state.savableItems;
    if (ingredients.isEmpty) {
      state = state.copyWith(
        menuStatus: MenuStatus.error,
        menuError: ScannerState.noSavableItems,
      );
      return;
    }
    state =
        state.copyWith(menuStatus: MenuStatus.generating, clearMenuError: true);
    try {
      final allergies = await ref.read(userAllergiesProvider.future);
      final dtos = await _api.generateMenu(
        GenerateMenuRequestDto(
            ingredients: ingredients, excludeAllergens: allergies),
      );
      state = state.copyWith(
        menuStatus: MenuStatus.ready,
        menu: dtos.map((d) => d.toEntity()).toList(),
      );
    } catch (e) {
      state = state.copyWith(
          menuStatus: MenuStatus.error, menuError: describeError(e));
    }
  }

  void reset() => state = const ScannerState();

  /// Back to the live camera; detected items stay in the tray.
  void resumeLive() =>
      state = state.copyWith(status: ScanStatus.idle, clearError: true);

  /// Re-opens the tray from the shutter row.
  void showTray() {
    if (state.items.isEmpty) return;
    state = state.copyWith(status: ScanStatus.detected);
  }

  // ---------------------------------------------------------------------------

  void _update(
      String id, DetectedIngredient Function(DetectedIngredient) change) {
    state = state.copyWith(
      items: [for (final i in state.items) i.id == id ? change(i) : i],
    );
  }

  /// Re-scans replace items of the same name; manual items are kept.
  List<DetectedIngredient> _merge(
      List<DetectedIngredient> current, List<DetectedIngredient> fresh) {
    final freshNames = fresh.map((i) => i.name.toLowerCase()).toSet();
    return [
      ...current
          .where((i) => i.manual && !freshNames.contains(i.name.toLowerCase())),
      ...fresh,
    ];
  }
}

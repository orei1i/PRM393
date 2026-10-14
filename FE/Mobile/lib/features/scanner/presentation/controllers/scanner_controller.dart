// lib/features/scanner/presentation/controllers/scanner_controller.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../data/models/scan_result_model.dart';
import '../../data/scanner_api_service.dart';
import '../../domain/entities/detected_ingredient.dart';

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

  List<DetectedIngredient> get confirmedItems => items.where((i) => i.confirmed).toList();
  int get pendingCount => items.where((i) => !i.confirmed).length;
  bool get isBusy => status == ScanStatus.analyzing || menuStatus == MenuStatus.generating;

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
    return ScannerState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      menuStatus: menuStatus ?? this.menuStatus,
      menu: menu ?? this.menu,
      menuError: clearMenuError ? null : (menuError ?? this.menuError),
    );
  }
}

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerState>(ScannerController.new);

class ScannerController extends Notifier<ScannerState> {
  ScannerApiService get _api => ref.read(scannerApiProvider);
  int _manualCounter = 0;

  @override
  ScannerState build() => const ScannerState();

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
      state = state.copyWith(status: ScanStatus.error, errorMessage: describeError(e));
    }
  }

  /// Low-confidence item → user picked the right name.
  void confirm(String id, {String? name}) => _update(id, (i) => i.copyWith(confirmed: true, name: name));

  void updateQuantity(String id, double quantity) {
    if (quantity <= 0) return;
    _update(id, (i) => i.copyWith(quantity: quantity));
  }

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

  void addManual(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    final exists = state.items.any((i) => i.name.toLowerCase() == name.toLowerCase());
    if (exists) return;
    _manualCounter++;
    final item = DetectedIngredient(
      id: 'manual_$_manualCounter',
      name: name,
      confidence: 1,
      freshness: Freshness.unknown,
      manual: true,
    );
    state = state.copyWith(items: [...state.items, item], status: ScanStatus.detected);
  }

  /// "Tạo thực đơn từ nguyên liệu này"
  Future<void> generateMenu() async {
    final ingredients = state.confirmedItems;
    if (ingredients.isEmpty) {
      state = state.copyWith(
        menuStatus: MenuStatus.error,
        menuError: 'Hãy xác nhận hoặc thêm ít nhất 1 nguyên liệu.',
      );
      return;
    }
    state = state.copyWith(menuStatus: MenuStatus.generating, clearMenuError: true);
    try {
      final allergies = await ref.read(userAllergiesProvider.future);
      final dtos = await _api.generateMenu(
        GenerateMenuRequestDto(ingredients: ingredients, excludeAllergens: allergies),
      );
      state = state.copyWith(
        menuStatus: MenuStatus.ready,
        menu: dtos.map((d) => d.toEntity()).toList(),
      );
    } catch (e) {
      state = state.copyWith(menuStatus: MenuStatus.error, menuError: describeError(e));
    }
  }

  void reset() => state = const ScannerState();

  /// Back to the live camera; detected items stay in the tray.
  void resumeLive() => state = state.copyWith(status: ScanStatus.idle, clearError: true);

  /// Re-opens the tray from the shutter row.
  void showTray() {
    if (state.items.isEmpty) return;
    state = state.copyWith(status: ScanStatus.detected);
  }

  // ---------------------------------------------------------------------------

  void _update(String id, DetectedIngredient Function(DetectedIngredient) change) {
    state = state.copyWith(
      items: [for (final i in state.items) i.id == id ? change(i) : i],
    );
  }

  /// Re-scans replace items of the same name; manual items are kept.
  List<DetectedIngredient> _merge(List<DetectedIngredient> current, List<DetectedIngredient> fresh) {
    final freshNames = fresh.map((i) => i.name.toLowerCase()).toSet();
    return [
      ...current.where((i) => i.manual && !freshNames.contains(i.name.toLowerCase())),
      ...fresh,
    ];
  }
}

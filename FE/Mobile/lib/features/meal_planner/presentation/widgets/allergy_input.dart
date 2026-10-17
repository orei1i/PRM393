// lib/features/meal_planner/presentation/widgets/allergy_input.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/utils/text_search.dart';
import '../../data/allergen_api_service.dart';

/// "Dị ứng" as free text: the member types what they react to, picks a
/// suggestion from the allergen catalog (accents optional: "dau phong" finds
/// "Đậu phộng") or presses Enter to keep their own words ("lá lốt"). Each
/// allergy is a chip with ✕. Keys follow `HealthProfile.allergies`.
class AllergyInput extends ConsumerStatefulWidget {
  const AllergyInput(
      {super.key, required this.values, required this.onChanged});

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<AllergyInput> createState() => _AllergyInputState();
}

class _AllergyInputState extends ConsumerState<AllergyInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<AllergenDto> _suggestions = const [];
  Timer? _debounce;
  int _query = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _has(String key) {
    final k = foldVietnamese(key.trim());
    return widget.values.any(
        (v) => foldVietnamese(v) == k || foldVietnamese(allergenLabel(v)) == k);
  }

  void _onText(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_query;
    try {
      final found =
          await ref.read(allergenApiProvider).search(text.trim(), limit: 6);
      if (!mounted || id != _query) return;
      setState(() => _suggestions =
          found.where((a) => !_has(a.key)).toList(growable: false));
    } catch (_) {
      // Suggestions are a convenience: typing and Enter still work.
      if (mounted && id == _query) setState(() => _suggestions = const []);
    }
  }

  void _add(String key) {
    final trimmed = key.trim();
    _debounce?.cancel();
    _query++;
    _controller.clear();
    setState(() => _suggestions = const []);
    if (trimmed.isEmpty || _has(trimmed)) return;
    widget.onChanged([...widget.values, trimmed]);
  }

  /// Enter: the suggestion with exactly this name, else the typed words.
  Future<void> _submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    AllergenDto? exact;
    for (final a in _suggestions) {
      if (a.isNamed(trimmed)) exact = a;
    }
    if (exact == null) {
      try {
        final found = await ref.read(allergenApiProvider).search(trimmed);
        exact = found.where((a) => a.isNamed(trimmed)).firstOrNull;
      } catch (_) {
        // Keep the member's own words.
      }
    }
    _add(exact?.key ?? trimmed);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('allergy-input'),
          controller: _controller,
          focusNode: _focus,
          onChanged: _onText,
          onSubmitted: _submit,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Nhập thành phần bạn dị ứng…',
            prefixIcon: const Icon(Icons.search_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Thêm dị ứng',
              onPressed: () => _submit(_controller.text),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty || _controller.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: vl.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final a in _suggestions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: Text(a.name),
                    subtitle: a.aliases.isEmpty
                        ? null
                        : Text('Gồm: ${a.aliases.join(', ')}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _add(a.key),
                  ),
                if (_controller.text.trim().isNotEmpty &&
                    !_suggestions.any((a) => a.isNamed(_controller.text)))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.edit_note_rounded),
                    title: Text('Thêm «${_controller.text.trim()}»'),
                    subtitle: const Text('Dùng đúng chữ bạn nhập'),
                    onTap: () => _add(_controller.text),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (widget.values.isEmpty)
          Text('Chưa khai báo dị ứng nào.',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in widget.values)
                InputChip(
                  label: Text(allergenLabel(key)),
                  deleteButtonTooltipMessage: 'Bỏ ${allergenLabel(key)}',
                  onDeleted: () =>
                      widget.onChanged([...widget.values]..remove(key)),
                ),
            ],
          ),
      ],
    );
  }
}

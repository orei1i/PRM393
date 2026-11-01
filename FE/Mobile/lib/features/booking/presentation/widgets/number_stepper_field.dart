// lib/features/booking/presentation/widgets/number_stepper_field.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/vl_colors.dart';

/// A whole number the member can step with − / + or type: number of days,
/// number of people. Typing outside the limits or leaving it empty shows a
/// message and reports `false` to [onValidityChanged], so the form can block
/// submit; moving the focus away clamps to the limits (empty: back to the last
/// valid number). [onChanged] only ever gets a number within the limits.
class NumberStepperField extends StatefulWidget {
  const NumberStepperField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.onValidityChanged,
    this.fieldKey,
  });

  final int value;
  final int min;
  final int max;

  /// "ngày", "người": the field's suffix and the buttons' tooltips.
  final String unit;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool>? onValidityChanged;

  /// Key of the text field, for tests.
  final Key? fieldKey;

  /// [value] within the limits, even when a stored chef limit makes them
  /// inverted (`min` wins). `clamp` throws on inverted limits.
  static int clampTo(int value, int min, int max) {
    final high = max < min ? min : max;
    return value < min ? min : (value > high ? high : value);
  }

  @override
  State<NumberStepperField> createState() => _NumberStepperFieldState();
}

class _NumberStepperFieldState extends State<NumberStepperField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  String? _error;

  int get _high => widget.max < widget.min ? widget.min : widget.max;

  int get _current =>
      NumberStepperField.clampTo(widget.value, widget.min, _high);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(NumberStepperField old) {
    super.didUpdateWidget(old);
    // A change from outside; never rewrite what is being typed.
    if (_error == null && int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setError(String? error) {
    if (error == _error) return;
    setState(() => _error = error);
    widget.onValidityChanged?.call(error == null);
  }

  String get _rangeMessage => 'Số ${widget.unit} từ ${widget.min} đến $_high.';

  void _onText(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < widget.min || n > _high) {
      _setError(_rangeMessage);
      return;
    }
    _setError(null);
    if (n != widget.value) widget.onChanged(n);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  /// The field's text becomes a number within the limits.
  void _commit() {
    if (!mounted) return;
    final n = int.tryParse(_controller.text.trim());
    final next =
        n == null ? _current : NumberStepperField.clampTo(n, widget.min, _high);
    _controller.text = '$next';
    _setError(null);
    if (next != widget.value) widget.onChanged(next);
  }

  void _step(int delta) {
    final base = int.tryParse(_controller.text.trim()) ?? _current;
    final next = NumberStepperField.clampTo(base + delta, widget.min, _high);
    _controller.text = '$next';
    _setError(null);
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final typed = int.tryParse(_controller.text.trim()) ?? _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Bớt 1 ${widget.unit}',
              onPressed: typed > widget.min ? () => _step(-1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: widget.fieldKey,
                controller: _controller,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                style: context.textStyles.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
                onChanged: _onText,
                onSubmitted: (_) => _commit(),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: widget.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Thêm 1 ${widget.unit}',
              onPressed: typed < _high ? () => _step(1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!,
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.colors.error)),
        ],
      ],
    );
  }
}

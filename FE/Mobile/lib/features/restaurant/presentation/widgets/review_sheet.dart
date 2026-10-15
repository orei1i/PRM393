// lib/features/restaurant/presentation/widgets/review_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/restaurant.dart';

/// Opens [ReviewSheet]; resolves to `true` once [onSubmit] succeeded.
Future<bool?> showReviewSheet(
  BuildContext context, {
  required String restaurantName,
  RestaurantReview? existing,
  required Future<void> Function(int rating, String comment) onSubmit,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ReviewSheet(
        restaurantName: restaurantName,
        existing: existing,
        onSubmit: onSubmit,
      ),
    );

/// "Viết đánh giá" / "Sửa đánh giá của bạn": 1–5 stars (required) and a
/// 10–500 character comment. Errors from [onSubmit] stay inside the sheet so
/// nothing typed is lost.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.restaurantName,
    required this.onSubmit,
    this.existing,
  });

  final String restaurantName;

  /// The member's current review: the sheet edits it.
  final RestaurantReview? existing;
  final Future<void> Function(int rating, String comment) onSubmit;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  static const _minLength = 10;
  static const _maxLength = 500;
  static const _starLabels = [
    'Rất tệ',
    'Chưa ổn',
    'Tạm được',
    'Ngon',
    'Tuyệt vời'
  ];

  final _form = GlobalKey<FormState>();
  late final _comment = TextEditingController(text: widget.existing?.comment);
  late int _rating = widget.existing?.rating ?? 0;
  bool _starsMissing = false;
  bool _attempted = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formOk = _form.currentState!.validate();
    setState(() {
      _starsMissing = _rating == 0;
      // From now on, messages update while typing.
      if (!formOk) _attempted = true;
    });
    if (!formOk || _rating == 0) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_rating, _comment.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _form,
          autovalidateMode: _attempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing ? 'Sửa đánh giá của bạn' : 'Viết đánh giá',
                  style: context.textStyles.titleLarge),
              const SizedBox(height: 4),
              Text(widget.restaurantName,
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted)),
              const SizedBox(height: 16),
              Wrap(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i sao',
                      isSelected: i <= _rating,
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                                _rating = i;
                                _starsMissing = false;
                              }),
                      iconSize: 36,
                      icon: Icon(Icons.star_outline_rounded,
                          color: context.vl.muted),
                      selectedIcon:
                          Icon(Icons.star_rounded, color: context.vl.caution),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _starsMissing
                      ? 'Chọn số sao'
                      : _rating == 0
                          ? 'Chạm để chấm điểm'
                          : _starLabels[_rating - 1],
                  style: context.textStyles.labelLarge?.copyWith(
                    color:
                        _starsMissing ? context.colors.error : context.vl.muted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _comment,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 6,
                maxLength: _maxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nhận xét',
                  hintText: 'Món nào ngon, phục vụ, giá cả…',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.length < _minLength) {
                    return 'Nhận xét cần ít nhất $_minLength ký tự';
                  }
                  if (text.length > _maxLength) {
                    return 'Tối đa $_maxLength ký tự';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 20, color: context.colors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: context.colors.error)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Gửi đánh giá'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

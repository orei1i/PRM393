// lib/features/recipe/presentation/widgets/recipe_review_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/recipe_review.dart';

/// "Đánh giá công thức" / "Sửa đánh giá của bạn": 1–5 stars (required) and
/// an optional text (10–500 chars). [onSubmit] saves it; errors stay in the
/// sheet with the input kept. `true` once saved.
Future<bool> showRecipeReviewSheet(
  BuildContext context, {
  RecipeReview? existing,
  required Future<void> Function(int rating, String? content) onSubmit,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReviewSheet(existing: existing, onSubmit: onSubmit),
  );
  return saved ?? false;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.existing, required this.onSubmit});

  final RecipeReview? existing;
  final Future<void> Function(int rating, String? content) onSubmit;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _formKey = GlobalKey<FormState>();
  late int? _rating = widget.existing?.rating;
  late final _content =
      TextEditingController(text: widget.existing?.content ?? '');
  bool _missingRating = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _missingRating = _rating == null);
    if (!formOk || _rating == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final text = _content.text.trim();
      await widget.onSubmit(_rating!, text.isEmpty ? null : text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final editing = widget.existing != null;
    final rating = _rating;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(editing ? 'Sửa đánh giá của bạn' : 'Đánh giá công thức',
                  style: context.textStyles.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i sao',
                      onPressed: _sending
                          ? null
                          : () => setState(() {
                                _rating = i;
                                _missingRating = false;
                              }),
                      icon: Icon(
                        rating != null && rating >= i
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 36,
                        color: vl.caution,
                      ),
                    ),
                ],
              ),
              Center(
                child: Text(
                  rating != null
                      ? reviewRatingLabels[rating - 1]
                      : _missingRating
                          ? 'Chọn số sao'
                          : 'Chạm để chọn số sao',
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: _missingRating && rating == null
                        ? context.colors.error
                        : vl.muted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _content,
                enabled: !_sending,
                maxLength: reviewContentMax,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nhận xét (không bắt buộc)',
                  hintText: 'Món có dễ nấu không, bạn đã đổi gì…',
                  alignLabelWithHint: true,
                ),
                validator: validateReviewContent,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.colors.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _sending ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: Text(_sending
                    ? 'Đang gửi…'
                    : editing
                        ? 'Lưu'
                        : 'Gửi đánh giá'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

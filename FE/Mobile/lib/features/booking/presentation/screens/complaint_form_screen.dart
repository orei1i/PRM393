// lib/features/booking/presentation/screens/complaint_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/data/media_api_service.dart';
import '../../../community/data/media_picker.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../widgets/booking_contract_tab.dart';

/// "Khiếu nại kế hoạch": reason, details, evidence (source links and up to
/// 5 photos) and the refund asked for. Submitting freezes the escrow until
/// an admin decides on the web console. Pops `true` once filed.
class ComplaintFormScreen extends ConsumerStatefulWidget {
  const ComplaintFormScreen({super.key, required this.booking});

  final BookingDto booking;

  static Route<bool> route(BookingDto booking) => MaterialPageRoute<bool>(
      builder: (_) => ComplaintFormScreen(booking: booking));

  @override
  ConsumerState<ComplaintFormScreen> createState() =>
      _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends ConsumerState<ComplaintFormScreen> {
  ComplaintReason? _reason;
  final _description = TextEditingController();
  final _link = TextEditingController();
  final _caption = TextEditingController();
  final _amount = TextEditingController();
  final _evidence = <EvidenceDto>[];
  RequestedOutcome _outcome = RequestedOutcome.fullRefund;
  bool _attempted = false;
  bool _uploading = false;
  bool _submitting = false;
  String? _linkError;

  int get _price => widget.booking.price ?? 0;

  @override
  void dispose() {
    _description.dispose();
    _link.dispose();
    _caption.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _addLink() {
    final url = _link.text.trim();
    if (!BookingRules.isHttpUrl(url)) {
      setState(() =>
          _linkError = 'Liên kết phải bắt đầu bằng http:// hoặc https://');
      return;
    }
    setState(() {
      _evidence.add(EvidenceDto(
          kind: EvidenceKind.link, url: url, caption: _caption.text.trim()));
      _link.clear();
      _caption.clear();
      _linkError = null;
    });
  }

  int get _imageCount =>
      _evidence.where((e) => e.kind == EvidenceKind.image).length;

  Future<void> _addImage() async {
    if (_imageCount >= BookingRules.maxEvidenceImages) return;
    final picked = await ref
        .read(mediaPickerProvider)
        .pick(context, kinds: const {MediaKind.image});
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await ref.read(mediaApiProvider).uploadImage(picked);
      if (!mounted) return;
      setState(() => _evidence.add(EvidenceDto(
          kind: EvidenceKind.image,
          url: uploaded.mediaUrl,
          caption: picked.name)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? get _evidenceError => _reason == null
      ? null
      : BookingRules.evidence(_reason!, _evidence.map((e) => e.kind));

  String? get _amountError => _outcome == RequestedOutcome.partialRefund
      ? BookingRules.partialRefund(int.tryParse(_amount.text.trim()), _price)
      : null;

  Future<void> _submit() async {
    final reason = _reason;
    final descriptionError =
        BookingRules.complaintDescription(_description.text);
    if (reason == null ||
        descriptionError != null ||
        _evidenceError != null ||
        _amountError != null) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(bookingApiProvider).fileComplaint(
            widget.booking.id,
            ComplaintRequestDto(
              reason: reason,
              description: _description.text.trim(),
              requestedOutcome: _outcome,
              requestedAmount: _outcome == RequestedOutcome.partialRefund
                  ? int.tryParse(_amount.text.trim())
                  : null,
              evidence: _evidence,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error =
        context.textStyles.bodySmall?.copyWith(color: context.colors.error);
    final escrow = widget.booking.escrow;
    return AskAiBubbleFree(
      child: Scaffold(
        appBar: AppBar(title: const Text('Khiếu nại kế hoạch')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            VLCard(
              color: context.vl.aiContainer,
              borderColor: Colors.transparent,
              child: Text(
                'Khi gửi khiếu nại, ${formatVnd(_price)} được tạm giữ'
                '${escrow == null ? '' : ' (thay vì chuyển cho chuyên gia lúc ${formatVnStamp(escrow.releaseAt)})'}'
                ' cho đến khi Ban quản trị quyết định. Tiền hoàn về phương thức thanh toán ban đầu.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.onAiContainer),
              ),
            ),
            const SizedBox(height: 16),
            Text('Lý do', style: context.textStyles.titleMedium),
            for (final r in ComplaintReason.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                selected: _reason == r,
                leading: Icon(_reason == r
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded),
                title: Text(r.label),
                onTap: () => setState(() => _reason = r),
              ),
            if (_attempted && _reason == null)
              Text('Chọn lý do khiếu nại.', style: error),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 4,
              maxLines: 10,
              maxLength: BookingRules.maxComplaintDescription,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Mô tả chi tiết',
                hintText:
                    'Ngày nào, món nào, vấn đề gì và ảnh hưởng tới bạn ra sao…',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: _attempted
                    ? BookingRules.complaintDescription(_description.text)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text('Bằng chứng', style: context.textStyles.titleMedium),
            Text(
              _reason == ComplaintReason.healthRisk
                  ? 'Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh'
                  : 'Ít nhất 1 bằng chứng: liên kết nguồn hoặc ảnh chụp kế hoạch.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
            for (final (i, e) in _evidence.indexed)
              EvidenceTile(
                evidence: e,
                onRemove: () => setState(() => _evidence.removeAt(i)),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Liên kết nguồn (http/https)',
                border: const OutlineInputBorder(),
                errorText: _linkError,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _caption,
              decoration: const InputDecoration(
                labelText: 'Chú thích (không bắt buộc)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _addLink,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Thêm liên kết nguồn'),
                ),
                OutlinedButton.icon(
                  onPressed: _uploading ||
                          _imageCount >= BookingRules.maxEvidenceImages
                      ? null
                      : _addImage,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                      'Thêm ảnh ($_imageCount/${BookingRules.maxEvidenceImages})'),
                ),
              ],
            ),
            if (_attempted && _evidenceError != null) ...[
              const SizedBox(height: 4),
              Text(_evidenceError!, style: error),
            ],
            const SizedBox(height: 16),
            Text('Yêu cầu', style: context.textStyles.titleMedium),
            const SizedBox(height: 6),
            SegmentedButton<RequestedOutcome>(
              segments: [
                for (final o in RequestedOutcome.values)
                  ButtonSegment(value: o, label: Text(o.label)),
              ],
              selected: {_outcome},
              onSelectionChanged: (s) => setState(() => _outcome = s.first),
            ),
            if (_outcome == RequestedOutcome.partialRefund) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Số tiền muốn hoàn (đ)',
                  helperText: 'Giá hợp đồng ${formatVnd(_price)}',
                  border: const OutlineInputBorder(),
                  errorText: _attempted ? _amountError : null,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting || _uploading ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_submitting ? 'Đang gửi…' : 'Gửi khiếu nại'),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/features/booking/presentation/widgets/booking_chat_tab.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/open_url.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../../community/data/media_api_service.dart';
import '../../../community/data/media_picker.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';

/// "Trao đổi": chat bubbles, system lines and offer cards ("Đồng ý" /
/// "Đề xuất giá khác" for the other party). An open offer stays answerable
/// after scrolling away from its card: a bar above the composer takes over. The
/// chef's first quote ("Báo giá") starts here too. Polls every 5 s while open.
/// Off-platform contact or payment words show a warning banner.
class BookingChatTab extends ConsumerStatefulWidget {
  const BookingChatTab({
    super.key,
    required this.booking,
    required this.party,
    required this.onAccept,
    required this.onCounter,
  });

  final BookingDto booking;
  final BookingParty party;
  final ValueChanged<OfferDto> onAccept;

  /// "Đề xuất giá" / "Đề xuất giá khác".
  final VoidCallback onCounter;

  static const pollEvery = Duration(seconds: 5);

  @override
  ConsumerState<BookingChatTab> createState() => _BookingChatTabState();
}

class _BookingChatTabState extends ConsumerState<BookingChatTab> {
  final _text = TextEditingController();
  final _listKey = GlobalKey();
  final _offerCardKey = GlobalKey();
  Timer? _poll;
  bool _sending = false;

  /// The buttons of the open offer's card are on screen.
  bool _offerCardVisible = true;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(BookingChatTab.pollEvery, (_) {
      if (!mounted) return;
      ref
        ..invalidate(bookingMessagesProvider(widget.booking.id))
        ..invalidate(bookingProvider(widget.booking.id));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  bool get _closed => const {
        BookingStatus.declined,
        BookingStatus.cancelled,
        BookingStatus.expired,
      }.contains(widget.booking.status);

  /// The offer waiting for this party's answer.
  OfferDto? get _answerable {
    final open = widget.booking.openOffer;
    return open != null &&
            open.proposedBy != widget.party &&
            widget.booking.status.canNegotiate
        ? open
        : null;
  }

  /// Where the card's buttons (its bottom edge) are against the list. A card
  /// that is built in the cache area or not built at all reads as not visible.
  void _checkOfferCard() {
    if (!mounted) return;
    var visible = false;
    final card = _offerCardKey.currentContext?.findRenderObject();
    final list = _listKey.currentContext?.findRenderObject();
    if (card is RenderBox &&
        list is RenderBox &&
        card.hasSize &&
        list.hasSize) {
      final bottom =
          card.localToGlobal(Offset(0, card.size.height), ancestor: list).dy;
      visible = bottom >= 48 && bottom <= list.size.height + 1;
    }
    if (visible != _offerCardVisible) {
      setState(() => _offerCardVisible = visible);
    }
  }

  Future<void> _send({String? attachmentUrl}) async {
    final body = _text.text.trim();
    final error = attachmentUrl == null ? BookingRules.message(body) : null;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(bookingApiProvider).sendMessage(
          widget.booking.id,
          SendMessageRequestDto(
              body:
                  attachmentUrl == null ? body : (body.isEmpty ? 'Ảnh' : body),
              attachmentUrl: attachmentUrl));
      _text.clear();
      ref.invalidate(bookingMessagesProvider(widget.booking.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final picked = await ref
        .read(mediaPickerProvider)
        .pick(context, kinds: const {MediaKind.image});
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final uploaded = await ref.read(mediaApiProvider).uploadImage(picked);
      if (!mounted) return;
      setState(() => _sending = false);
      await _send(attachmentUrl: uploaded.absoluteUrl);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingMessagesProvider(widget.booking.id));
    final messages = async.valueOrNull ?? const <MessageDto>[];
    final answerable = _answerable;
    final awaitingQuote = widget.party == BookingParty.chef &&
        widget.booking.status == BookingStatus.requested;
    // Messages can arrive or the offer can change without a scroll.
    if (answerable != null && messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOfferCard());
    }
    final offPlatform = messages.any((m) =>
            m.kind == MessageKind.text &&
            BookingRules.mentionsOffPlatform(m.body)) ||
        BookingRules.mentionsOffPlatform(_text.text);
    return Column(
      children: [
        if (offPlatform)
          Container(
            width: double.infinity,
            color: context.vl.cautionContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: context.vl.onCautionContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Giao dịch ngoài VeganLife không được bảo vệ bởi cơ chế giữ tiền',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.onCautionContainer),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (async) {
            AsyncValue(valueOrNull: final value?) => value.isEmpty
                ? Center(
                    child: Text('Chưa có tin nhắn.',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.vl.muted)),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _checkOfferCard();
                      return false;
                    },
                    child: ListView.builder(
                      key: _listKey,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: value.length,
                      itemBuilder: (context, i) {
                        final m = value[value.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MessageItem(
                            message: m,
                            booking: widget.booking,
                            party: widget.party,
                            offerCardKey:
                                m.offer != null && m.offer!.id == answerable?.id
                                    ? _offerCardKey
                                    : null,
                            onAccept: widget.onAccept,
                            onCounter: widget.onCounter,
                          ),
                        );
                      },
                    ),
                  ),
            AsyncError(:final error) => Center(
                child: SingleChildScrollView(
                  child: ErrorStateView(
                      error: error,
                      onRetry: () => ref.invalidate(
                          bookingMessagesProvider(widget.booking.id))),
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
        if (answerable != null && !_offerCardVisible)
          _PinnedOfferBar(
            offer: answerable,
            onAccept: () => widget.onAccept(answerable),
            onCounter: widget.onCounter,
          ),
        if (awaitingQuote)
          _QuotePrompt(busy: _sending, onQuote: widget.onCounter),
        if (!_closed)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  if (widget.booking.status.canNegotiate)
                    IconButton.filledTonal(
                      tooltip: 'Đề xuất giá',
                      onPressed: _sending ? null : widget.onCounter,
                      icon: const Icon(Icons.request_quote_outlined),
                    ),
                  IconButton(
                    tooltip: 'Gửi ảnh',
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: BookingRules.maxMessage,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText:
                            'Nhắn cho ${widget.party == BookingParty.chef ? 'thành viên' : 'chuyên gia'}…',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Gửi',
                    onPressed: _sending || _text.text.trim().isEmpty
                        ? null
                        : () => _send(),
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The open offer when its card is scrolled out of view: same two answers.
class _PinnedOfferBar extends StatelessWidget {
  const _PinnedOfferBar({
    required this.offer,
    required this.onAccept,
    required this.onCounter,
  });

  final OfferDto offer;
  final VoidCallback onAccept;
  final VoidCallback onCounter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.vl.cautionContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Đề xuất ${formatVnd(offer.price)} · ${offer.planDays} ngày đang chờ bạn trả lời',
                style: context.textStyles.bodySmall?.copyWith(
                    color: context.vl.onCautionContainer,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(onPressed: onAccept, child: const Text('Đồng ý')),
                OutlinedButton(
                    onPressed: onCounter,
                    child: const Text('Đề xuất giá khác')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chef's first quote: the action lives in the chat, not above it.
class _QuotePrompt extends StatelessWidget {
  const _QuotePrompt({required this.busy, required this.onQuote});

  final bool busy;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('Gửi giá đầu tiên cho thành viên.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : onQuote,
            icon: const Icon(Icons.request_quote_outlined, size: 18),
            label: const Text('Báo giá'),
          ),
        ],
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({
    required this.message,
    required this.booking,
    required this.party,
    required this.onAccept,
    required this.onCounter,
    this.offerCardKey,
  });

  final MessageDto message;
  final BookingDto booking;
  final BookingParty party;

  /// On the card of the offer waiting for an answer.
  final Key? offerCardKey;
  final ValueChanged<OfferDto> onAccept;
  final VoidCallback onCounter;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final time = formatVnStamp(m.createdAt);
    if (m.senderRole == BookingParty.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          '${m.body}\n$time',
          textAlign: TextAlign.center,
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
      );
    }
    final mine = m.senderRole == party;
    final offer = m.offer;
    final colors = context.colors;
    final content = offer != null
        ? OfferCard(
            key: offerCardKey,
            offer: offer,
            mine: mine,
            canAnswer: !mine &&
                offer.isOpen &&
                booking.currentOffer?.id == offer.id &&
                booking.status.canNegotiate,
            onAccept: () => onAccept(offer),
            onCounter: onCounter,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? colors.primaryContainer : colors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.attachmentUrl != null)
                  _AttachmentTile(url: m.attachmentUrl!),
                if (m.body.isNotEmpty)
                  Text(m.body,
                      style: context.textStyles.bodyMedium?.copyWith(
                          color: mine
                              ? colors.onPrimaryContainer
                              : colors.onSurface)),
              ],
            ),
          );
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          child: content,
        ),
        const SizedBox(height: 2),
        Text(
          '${mine ? 'Bạn' : (m.senderRole == BookingParty.chef ? booking.chef.fullName : booking.member.fullName)} · $time',
          style:
              context.textStyles.labelSmall?.copyWith(color: context.vl.muted),
        ),
      ],
    );
  }
}

/// An image sent in the chat; opens in the browser (no inline download).
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(url),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Ảnh đính kèm · Mở',
                  style: context.textStyles.labelLarge
                      ?.copyWith(decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Đề xuất giá · 1.500.000đ · 10 ngày · Có phản hồi mỗi ngày · bắt đầu
/// 20/10" + note + status; the other party answers here.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.mine,
    required this.canAnswer,
    required this.onAccept,
    required this.onCounter,
  });

  final OfferDto offer;
  final bool mine;
  final bool canAnswer;
  final VoidCallback onAccept;
  final VoidCallback onCounter;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (Color bg, Color fg) = switch (offer.status) {
      OfferStatus.open => (vl.cautionContainer, vl.onCautionContainer),
      OfferStatus.accepted => (vl.successContainer, vl.onSuccessContainer),
      OfferStatus.rejected => (
          context.colors.errorContainer,
          context.colors.onErrorContainer
        ),
      _ => (context.colors.surfaceContainer, context.colors.onSurfaceVariant),
    };
    return VLCard(
      padding: const EdgeInsets.all(12),
      borderColor: offer.isOpen ? context.colors.primary : context.vl.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined,
                  size: 18, color: context.colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Đề xuất giá · ${formatVnd(offer.price)}',
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${offer.planDays} ngày · ${offer.bookingType.label} · bắt đầu ${formatDayMonth(offer.startDate)}',
              style: context.textStyles.bodySmall),
          if (offer.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(offer.note, style: context.textStyles.bodyMedium),
          ],
          const SizedBox(height: 8),
          StatusPill(label: offer.status.label, background: bg, foreground: fg),
          if (canAnswer) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(onPressed: onAccept, child: const Text('Đồng ý')),
                OutlinedButton(
                    onPressed: onCounter,
                    child: const Text('Đề xuất giá khác')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// lib/features/booking/presentation/screens/booking_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef_studio/data/chef_studio_api_service.dart';
import '../../../commerce/presentation/screens/payment_screen.dart';
import '../../../meal_planner/data/models/meal_plan_model.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_chat_tab.dart';
import '../widgets/booking_contract_tab.dart';
import '../widgets/booking_plan_tab.dart';
import '../widgets/booking_sheets.dart';
import '../widgets/booking_ui.dart';
import 'complaint_form_screen.dart';
import 'plan_editor_screen.dart';

/// One booking, for either party: header (other party, status, the 5-step
/// progress and the actions of the moment) and the tabs "Trao đổi" (chat
/// and offers), "Kế hoạch" (plan days) and "Hợp đồng" (contract, escrow,
/// request and complaint).
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen(
      {super.key, required this.bookingId, this.initialTab = 0});

  final String bookingId;

  /// 0 Trao đổi · 1 Kế hoạch · 2 Hợp đồng.
  final int initialTab;

  static Route<void> route(String bookingId, {int initialTab = 0}) =>
      MaterialPageRoute<void>(
        builder: (_) =>
            BookingDetailScreen(bookingId: bookingId, initialTab: initialTab),
      );

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;

  BookingApiService get _api => ref.read(bookingApiProvider);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Runs [action] with a busy flag; errors become a snackbar; every list
  /// refetches afterwards.
  Future<bool> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      ref.bookingChanged();
      if (done != null) _snack(done);
      return true;
    } catch (e) {
      if (mounted) _snack(describeError(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- actions --------------------------------------------------------------

  Future<void> _pay(BookingDto b) async {
    final navigator = Navigator.of(context);
    String? orderId;
    final ok = await _run(() async {
      orderId = (await _api.startPayment(b.id)).id;
    });
    if (!ok || orderId == null || !mounted) return;
    await navigator.push(PaymentScreen.route(orderId!));
    if (mounted) ref.bookingChanged();
  }

  Future<void> _cancel(BookingDto b) async {
    final reason = await showReasonSheet(
      context,
      title: 'Huỷ yêu cầu',
      message: 'Chuyên gia sẽ nhận được lý do. Bạn chưa bị trừ tiền.',
      hint: 'VD: Mình đổi lịch, chưa cần thực đơn lúc này',
      confirmLabel: 'Huỷ yêu cầu',
      validate: BookingRules.cancelReason,
    );
    if (reason == null || !mounted) return;
    await _run(() => _api.cancel(b.id, reason), done: 'Đã huỷ yêu cầu.');
  }

  Future<void> _decline(BookingDto b) async {
    final reason = await showReasonSheet(
      context,
      title: 'Từ chối yêu cầu',
      message: 'Thành viên sẽ nhận được lý do. Bạn có thể từ chối đến trước '
          'khi thành viên thanh toán.',
      hint: 'VD: Lịch của mình đã kín trong 2 tuần tới',
      confirmLabel: 'Từ chối',
      validate: BookingRules.declineReason,
    );
    if (reason == null || !mounted) return;
    await _run(() => _api.decline(b.id, reason), done: 'Đã từ chối yêu cầu.');
  }

  /// The chef's first quote, prefilled from their listed prices.
  Future<OfferRequestDto> _chefInitialOffer(BookingDto b) async {
    var perDay = b.bookingType == BookingType.dailyFeedback ? 180000 : 120000;
    try {
      final me = await ref.read(chefStudioApiProvider).getMyProfile();
      perDay = b.bookingType == BookingType.dailyFeedback
          ? me.feedbackPricePerDay
          : me.pricePerDay;
    } on ApiException {
      // Keep the default price; the chef edits it anyway.
    }
    return OfferRequestDto(
      price: perDay * b.planDays,
      planDays: b.planDays,
      bookingType: b.bookingType,
      startDate: b.startDate,
    );
  }

  /// "Báo giá" / "Đề xuất giá" / "Đề xuất giá khác".
  Future<void> _offer(BookingDto b, BookingParty party) async {
    final current = b.currentOffer;
    final initial = current != null
        ? OfferRequestDto(
            price: current.price,
            planDays: current.planDays,
            bookingType: current.bookingType,
            startDate: current.startDate,
          )
        : party == BookingParty.chef
            ? await _chefInitialOffer(b)
            : OfferRequestDto(
                price: (b.budgetPerDay ?? 120000) * b.planDays,
                planDays: b.planDays,
                bookingType: b.bookingType,
                startDate: b.startDate,
              );
    if (!mounted) return;
    final request = await showPriceOfferSheet(
      context,
      initial: initial,
      title: party == BookingParty.chef && current == null
          ? 'Báo giá'
          : current != null && current.proposedBy != party
              ? 'Đề xuất giá khác'
              : 'Đề xuất giá',
    );
    if (request == null || !mounted) return;
    await _run(() => _api.sendOffer(b.id, request), done: 'Đã gửi đề xuất.');
  }

  Future<void> _accept(BookingDto b, OfferDto offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Đồng ý ${formatVnd(offer.price)}?'),
        content: Text(
          '${offer.planDays} ngày · ${offer.bookingType.label} · bắt đầu '
          '${formatDayMonth(offer.startDate)}.\nHồ sơ hợp đồng sẽ được tạo; '
          'thành viên có 48 giờ để thanh toán, tiền được VeganLife giữ đến '
          '3 ngày sau khi kế hoạch kết thúc.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Xem lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Đồng ý')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => _api.respondToOffer(b.id, offer.id, accept: true),
        done: 'Đã tạo hồ sơ hợp đồng.');
  }

  Future<void> _complain(BookingDto b) async {
    final filed =
        await Navigator.of(context).push(ComplaintFormScreen.route(b));
    if (filed == true && mounted) {
      ref.bookingChanged();
      _snack('Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc.');
    }
  }

  Future<void> _compose(BookingDto b) async {
    await Navigator.of(context).push(PlanEditorScreen.route(b.id));
    if (mounted) ref.bookingChanged();
  }

  Future<void> _respondComplaint(BookingDto b) async {
    final request = await showComplaintResponseSheet(context);
    if (request == null || !mounted) return;
    await _run(() => _api.respondToComplaint(b.id, request),
        done: 'Đã gửi phản hồi cho Ban quản trị.');
  }

  Future<void> _feedback(BookingDto b, PlanDayDto day) async {
    final feedback = await showDayFeedbackSheet(context, day: day);
    if (feedback == null || !mounted) return;
    await _run(() => _api.sendDayFeedback(b.id, day.dayIndex, feedback),
        done: 'Đã gửi phản hồi. Chuyên gia sẽ chỉnh ngày tiếp theo.');
  }

  /// "Áp dụng kế hoạch vào Thực đơn": every sent meal into its date and
  /// slot of the current week (the planner skips days outside it).
  Future<void> _applyToPlanner(BookingDto b, List<PlanDayDto> days) async {
    final requests = [
      for (final d in days)
        if (d.isSent)
          for (final m in d.meals)
            AddMealRequestDto(
              date: d.date,
              slot: m.slot,
              name: m.recipe.name,
              calories: m.recipe.calories,
              proteinG: m.recipe.proteinG,
              carbsG: m.recipe.carbsG,
              fatG: m.recipe.fatG,
              ingredients: m.recipe.ingredients,
              source: 'chef',
              sourceId: m.recipe.id.isEmpty ? null : m.recipe.id,
              sourceName: b.chef.fullName,
            ),
    ];
    if (requests.isEmpty) return;
    var placed = 0;
    final ok = await _run(() async {
      placed = await ref
          .read(mealPlanControllerProvider.notifier)
          .addMeals(requests);
    });
    if (!ok || !mounted) return;
    _snack(placed == requests.length
        ? 'Đã thêm $placed món vào Thực đơn.'
        : placed == 0
            ? 'Các ngày của kế hoạch nằm ngoài tuần hiện tại của Thực đơn.'
            : 'Đã thêm $placed/${requests.length} món vào Thực đơn tuần này; '
                'các ngày ngoài tuần chưa thêm được.');
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingProvider(widget.bookingId));
    final me = ref.watch(sessionControllerProvider.select((s) => s.userId));
    final booking = async.valueOrNull;
    final party = booking?.partyOf(me);
    return AskAiBubbleFree(
      child: DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab.clamp(0, 2),
        child: Scaffold(
          appBar: AppBar(
            title: Text(booking == null
                ? 'Đặt chuyên gia'
                : party == BookingParty.chef
                    ? booking.member.fullName
                    : booking.chef.fullName),
            bottom: booking == null
                ? null
                : const TabBar(
                    tabs: [
                      Tab(text: 'Trao đổi'),
                      Tab(text: 'Kế hoạch'),
                      Tab(text: 'Hợp đồng'),
                    ],
                  ),
          ),
          body: switch (async) {
            AsyncValue(:final value?) when party != null => _body(value, party),
            AsyncValue(:final value?) when party == null => Center(
                child: EmptyStateView(
                  icon: Icons.lock_outline_rounded,
                  title: 'Không xem được yêu cầu này',
                  message:
                      'Yêu cầu thuộc về ${value.member.fullName} và ${value.chef.fullName}.',
                ),
              ),
            AsyncError(:final error) => Center(
                child: SingleChildScrollView(
                  child: ErrorStateView(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(bookingProvider(widget.bookingId))),
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _body(BookingDto b, BookingParty party) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: _Header(
              booking: b,
              party: party,
              busy: _busy,
              actions: _actions(b, party),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            children: [
              BookingChatTab(
                booking: b,
                party: party,
                onAccept: (offer) => _accept(b, offer),
                onCounter: () => _offer(b, party),
              ),
              BookingPlanTab(
                booking: b,
                party: party,
                busy: _busy,
                onFeedback: (day) => _feedback(b, day),
                onApply: (days) => _applyToPlanner(b, days),
                onCompose: () => _compose(b),
              ),
              BookingContractTab(booking: b, party: party),
            ],
          ),
        ),
      ],
    );
  }

  /// The actions of the moment, by status and party.
  List<Widget> _actions(BookingDto b, BookingParty party) {
    final disabled = _busy;
    final now = DateTime.now();
    Widget filled(String label, IconData icon, VoidCallback onPressed) =>
        FilledButton.icon(
          onPressed: disabled ? null : onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    Widget outlined(String label, VoidCallback onPressed) => OutlinedButton(
        onPressed: disabled ? null : onPressed, child: Text(label));
    final open = b.openOffer;

    if (party == BookingParty.member) {
      return [
        if (b.status == BookingStatus.awaitingPayment && b.contract != null)
          filled('Thanh toán ${formatVnd(b.contract!.price)}',
              Icons.qr_code_2_rounded, () => _pay(b)),
        if (b.status.canNegotiate &&
            open != null &&
            open.proposedBy == BookingParty.chef) ...[
          filled('Đồng ý ${formatVnd(open.price)}', Icons.handshake_outlined,
              () => _accept(b, open)),
          outlined('Đề xuất giá khác', () => _offer(b, party)),
        ],
        if (b.canComplain(now)) outlined('Khiếu nại', () => _complain(b)),
        if (b.status.isBeforePayment) outlined('Huỷ yêu cầu', () => _cancel(b)),
      ];
    }
    return [
      if (b.status == BookingStatus.requested)
        filled('Báo giá', Icons.request_quote_outlined, () => _offer(b, party)),
      if (b.status == BookingStatus.negotiating &&
          open != null &&
          open.proposedBy == BookingParty.member) ...[
        filled('Đồng ý ${formatVnd(open.price)}', Icons.handshake_outlined,
            () => _accept(b, open)),
        outlined('Đề xuất giá khác', () => _offer(b, party)),
      ],
      if (b.status == BookingStatus.active || b.status == BookingStatus.ended)
        if (b.deliveredDays < b.planDays)
          filled(
              'Soạn kế hoạch', Icons.edit_calendar_outlined, () => _compose(b)),
      if (b.status == BookingStatus.disputed &&
          b.complaint?.chefResponse == null)
        filled('Phản hồi khiếu nại', Icons.gavel_rounded,
            () => _respondComplaint(b)),
      if (b.status.isBeforePayment) outlined('Từ chối', () => _decline(b)),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.booking,
    required this.party,
    required this.busy,
    required this.actions,
  });

  final BookingDto booking;
  final BookingParty party;
  final bool busy;
  final List<Widget> actions;

  String? _hint() {
    final b = booking;
    final asChef = party == BookingParty.chef;
    final open = b.openOffer;
    return switch (b.status) {
      BookingStatus.requested => asChef
          ? 'Thành viên chờ bạn báo giá.'
          : 'Chuyên gia đang xem yêu cầu và sẽ báo giá trong chat.',
      BookingStatus.negotiating => open == null
          ? 'Đang trao đổi giá trong chat.'
          : open.proposedBy == party
              ? 'Đang chờ ${asChef ? 'thành viên' : 'chuyên gia'} trả lời đề xuất ${formatVnd(open.price)}.'
              : 'Bạn có đề xuất ${formatVnd(open.price)} chờ trả lời.',
      BookingStatus.awaitingPayment => b.contract == null
          ? null
          : asChef
              ? 'Chờ thành viên thanh toán trước ${formatVnStamp(b.contract!.paymentDueAt)}.'
              : 'Thanh toán trước ${formatVnStamp(b.contract!.paymentDueAt)}, nếu không yêu cầu sẽ hết hiệu lực.',
      BookingStatus.active || BookingStatus.ended => b.escrow == null
          ? null
          : 'Tiền được VeganLife giữ đến ${formatVnStamp(b.escrow!.releaseAt)}.',
      BookingStatus.disputed => asChef
          ? (b.complaint?.chefResponse == null
              ? 'Thành viên đã khiếu nại. Hãy phản hồi để Ban quản trị xem xét.'
              : 'Ban quản trị đang xem xét khiếu nại.')
          : 'Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc.',
      BookingStatus.declined =>
        'Chuyên gia từ chối: ${b.declineReason ?? ''}'.trim(),
      BookingStatus.cancelled => 'Đã huỷ: ${b.cancelReason ?? ''}'.trim(),
      BookingStatus.expired => 'Quá hạn thanh toán 48 giờ.',
      BookingStatus.completed || BookingStatus.resolved => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final other = party == BookingParty.chef ? b.member : b.chef;
    final price = b.price;
    final hint = _hint();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            UserAvatar(
                name: other.fullName,
                size: 44,
                verified: party == BookingParty.member),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(planSummary(b.planDays, b.bookingType),
                      style: context.textStyles.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    [
                      formatDateRange(b.startDate, b.endDate),
                      if (price != null) formatVnd(price),
                    ].join(' · '),
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            bookingStatusTag(context, b.status),
          ],
        ),
        const SizedBox(height: 10),
        BookingStepper(booking: b),
        if (hint != null && hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          VLCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: context.vl.aiContainer,
            borderColor: Colors.transparent,
            child: Text(hint,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.onAiContainer)),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: actions),
        ],
        if (busy) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }
}

// lib/features/booking/presentation/screens/booking_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/config/backend_modules.dart';
import '../../../../core/navigation/app_nav.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/mock_persona.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef_studio/data/chef_studio_api_service.dart';
import '../../../commerce/presentation/screens/payment_screen.dart';
import '../../../meal_planner/data/models/meal_plan_model.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../../domain/booking_views.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_chat_tab.dart';
import '../widgets/booking_contract_tab.dart';
import '../widgets/booking_plan_tab.dart';
import '../widgets/booking_sheets.dart';
import '../widgets/booking_ui.dart';
import 'complaint_form_screen.dart';
import 'plan_editor_screen.dart';

/// One booking, for either party: header (other party, status, the 5-step
/// progress and the actions of the moment; offers are answered only on their
/// card in the chat) and the tabs "Trao đổi" (chat and offers), "Kế hoạch"
/// (plan days) and "Hợp đồng" (contract, money stages, request and complaint).
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen(
      {super.key, required this.bookingId, this.initialTab = 0});

  final String bookingId;

  /// 0 Trao đổi · 1 Kế hoạch · 2 Hợp đồng.
  final int initialTab;

  static Route<void> route(String bookingId, {int initialTab = 0}) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.booking(bookingId)),
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

  /// Opens the payment screen from the order, which exists once an offer is
  /// accepted. The QR is asked for there: without a gateway (503) the member
  /// stays on that screen, told so, and can still pay from the wallet.
  Future<void> _pay(BookingDto b) async {
    final orderId = b.paymentOrderId;
    if (orderId == null) {
      _snack('Chưa có đơn thanh toán cho yêu cầu này. Bạn thử lại sau nhé.');
      ref.bookingChanged();
      return;
    }
    await Navigator.of(context)
        .push(PaymentScreen.route(orderId, autoRenew: true));
    if (mounted) ref.bookingChanged();
  }

  Future<void> _cancel(BookingDto b) async {
    final paid = b.escrow != null;
    final price = b.contract?.price ?? 0;
    final reason = await showReasonSheet(
      context,
      title: 'Huỷ yêu cầu',
      message: paid
          ? 'Chuyên gia chưa gửi ngày nào và sẽ nhận được lý do. '
              '${formatVnd(price)} được hoàn vào Ví của tôi.'
          : 'Chuyên gia sẽ nhận được lý do. Bạn chưa bị trừ tiền.',
      hint: 'VD: Mình đổi lịch, chưa cần thực đơn lúc này',
      confirmLabel: 'Huỷ yêu cầu',
      validate: BookingRules.cancelReason,
    );
    if (reason == null || !mounted) return;
    await _run(() => _api.cancel(b.id, reason),
        done: paid
            ? 'Đã huỷ yêu cầu. ${formatVnd(price)} đã vào Ví của tôi.'
            : 'Đã huỷ yêu cầu.');
  }

  /// "Không đồng ý": closes the deal before payment, for both sides.
  Future<void> _decline(BookingDto b) async {
    final reason = await showReasonSheet(
      context,
      title: 'Không đồng ý',
      message: 'Yêu cầu sẽ đóng lại và thành viên nhận được lý do. Thành viên '
          'không bị trừ tiền; hai bên không trao đổi tiếp được trong yêu cầu này.',
      hint: 'VD: Lịch của mình đã kín trong 2 tuần tới',
      confirmLabel: 'Không đồng ý',
      validate: BookingRules.declineReason,
    );
    if (reason == null || !mounted) return;
    await _run(() => _api.decline(b.id, reason),
        done: 'Đã báo không đồng ý. Thành viên không bị trừ tiền.');
  }

  /// "Xác nhận hoàn thành": the contract is completed and the hold starts.
  Future<void> _confirmCompletion(BookingDto b) async {
    final contract = b.contract;
    final net = contract == null ? 0 : contract.price - contract.fee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận hoàn thành?'),
        content: Text(
          'Bạn đã giao đủ ${b.planDays} ngày. Hợp đồng hoàn thành ngay, VeganLife '
          'giữ tiền thêm ${BookingRules.holdDays} ngày; không có khiếu nại thì '
          '${formatVnd(net)} (sau phí) vào ví của bạn.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Xem lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => _api.confirmCompletion(b.id),
        done:
            'Đã hoàn thành hợp đồng. Tiền giữ ${BookingRules.holdDays} ngày rồi vào ví của bạn.');
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

  /// "Báo giá" / "Đề xuất giá" / "Đề xuất giá khác", all from the chat.
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

  /// The member goes straight on to the payment screen; when the chef accepts
  /// a counter-offer, the member finds "Thanh toán" on the booking.
  Future<void> _accept(BookingDto b, OfferDto offer, BookingParty party) async {
    final asMember = party == BookingParty.member;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Đồng ý ${formatVnd(offer.price)}?'),
        content: Text(
          '${offer.planDays} ngày · ${offer.bookingType.label} · bắt đầu '
          '${formatDayMonth(offer.startDate)}.\nHồ sơ hợp đồng sẽ được tạo; '
          '${asMember ? 'bạn' : 'thành viên'} có 48 giờ để thanh toán (chậm nhất '
          'trước ngày bắt đầu), tiền được VeganLife giữ đến '
          '${BookingRules.holdDays} ngày sau khi hợp đồng hoàn thành.',
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
    BookingDto? accepted;
    final done = await _run(() async {
      accepted = await _api.respondToOffer(b.id, offer.id, accept: true);
    },
        done: asMember
            ? null
            : 'Đã tạo hồ sơ hợp đồng. Chờ thành viên thanh toán.');
    if (done && asMember && mounted && accepted != null) await _pay(accepted!);
  }

  Future<void> _complain(BookingDto b) async {
    final filed =
        await Navigator.of(context).push(ComplaintFormScreen.route(b));
    if (filed == true && mounted) {
      ref.bookingChanged();
      _snack('Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc.');
    }
  }

  /// "Soạn kế hoạch"; the editor closes itself once the whole plan is sent.
  Future<void> _compose(BookingDto b) async {
    final sentAll =
        await Navigator.of(context).push(PlanEditorScreen.route(b.id));
    if (!mounted) return;
    ref.bookingChanged();
    if (sentAll == true) _snack('Đã gửi toàn bộ kế hoạch');
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

  /// How many of [requests] would replace another dish in the current week.
  /// 0 when the planner can't load: applying then fails with its own message.
  Future<int> _mealsOverwrittenBy(List<AddMealRequestDto> requests) async {
    final MealPlan? plan;
    try {
      plan = (await ref.read(mealPlanControllerProvider.future)).plan;
    } catch (_) {
      return 0;
    }
    return requests.where((r) {
      final held = plan?.dayFor(r.date)?.meals[r.slot];
      return held != null && held.name != r.name;
    }).length;
  }

  /// The week may hold meals the member chose: says how many go before they do.
  Future<bool> _confirmOverwrite(int overwritten, int total) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Thay $overwritten món đang có?'),
        content: Text('Kế hoạch có $total món. $overwritten bữa trong Thực đơn '
            'tuần này đang có món khác và sẽ được thay thế; thao tác này không '
            'hoàn tác được.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Thay và áp dụng')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// "Áp dụng kế hoạch vào Thực đơn": every sent meal into its date and
  /// slot of the current week (the planner skips days outside it), after a
  /// confirmation if that replaces other dishes, then "Xem Thực đơn" in the
  /// snackbar.
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
              instructions: m.recipe.instructions,
            ),
    ];
    if (requests.isEmpty) return;
    var overwritten = 0;
    if (!await _run(() async {
      overwritten = await _mealsOverwrittenBy(requests);
    })) {
      return;
    }
    if (!mounted) return;
    if (overwritten > 0 &&
        (!await _confirmOverwrite(overwritten, requests.length) || !mounted)) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final tabs = ref.read(shellTabProvider.notifier);
    var placed = 0;
    final ok = await _run(() async {
      placed = await ref
          .read(mealPlanControllerProvider.notifier)
          .addMeals(requests);
    });
    if (!ok || !mounted) return;
    if (placed == 0) {
      _snack('Các ngày của kế hoạch nằm ngoài tuần hiện tại của Thực đơn.');
      return;
    }

    // "Xem Thực đơn": the Thực đơn tab, from here or wherever the member
    // went since (the snackbar outlives this page).
    void openPlanner() {
      if (mounted) {
        AppNav.toShellTab(navigator, ref, ShellTab.planner);
      } else {
        navigator.popUntil((r) => r.isFirst);
        tabs.select(ShellTab.planner);
      }
    }

    // The action names the destination, so the message doesn't repeat it.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        persist: MediaQuery.accessibleNavigationOf(context),
        content: Text(placed == requests.length
            ? 'Đã thêm $placed món của kế hoạch vào tuần này.'
            : 'Đã thêm $placed/${requests.length} món vào tuần này; các '
                'ngày ngoài tuần chưa thêm được.'),
        action: SnackBarAction(label: 'Xem Thực đơn', onPressed: openPlanner),
      ));
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingProvider(widget.bookingId));
    final me = ref.watch(sessionControllerProvider
        .select((s) => moduleUserId(BackendModule.bookings, s)));
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
                    // Three labels still fit at 360 dp with large text.
                    labelPadding: EdgeInsets.symmetric(horizontal: 4),
                    tabs: [
                      Tab(text: 'Trao đổi'),
                      Tab(text: 'Kế hoạch'),
                      Tab(text: 'Hợp đồng'),
                    ],
                  ),
          ),
          body: DemoDataBanner.wrap(BackendModule.bookings,
              child: switch (async) {
                AsyncValue(valueOrNull: final value?) when party != null =>
                  _body(value, party),
                AsyncValue(valueOrNull: final value?) when party == null =>
                  Center(
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
                          onRetry: () => ref
                              .invalidate(bookingProvider(widget.bookingId))),
                    ),
                  ),
                _ => const Center(child: CircularProgressIndicator()),
              }),
        ),
      ),
    );
  }

  Widget _body(BookingDto b, BookingParty party) {
    final actions = _actions(b, party);
    // On a small screen with large text the header scrolls: the actions stay in
    // sight below it. With the keyboard up the chat needs that room.
    final pinActions =
        actions.isNotEmpty && MediaQuery.viewInsetsOf(context).bottom == 0;
    // Of what is left of the screen, so the keyboard can't squeeze the chat out.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: constraints.maxHeight * 0.42),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: _Header(
                booking: b,
                party: party,
                busy: _busy,
                actions: pinActions ? const [] : actions,
              ),
            ),
          ),
          if (pinActions)
            Padding(
              key: const ValueKey('booking-actions'),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 6, children: actions),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                BookingChatTab(
                  booking: b,
                  party: party,
                  onAccept: (offer) => _accept(b, offer, party),
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
      ),
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

    if (party == BookingParty.member) {
      return [
        if (b.status == BookingStatus.awaitingPayment && b.contract != null)
          filled('Thanh toán ${formatVnd(b.contract!.price)}',
              Icons.qr_code_2_rounded, () => _pay(b)),
        if (b.canComplain(now)) outlined('Khiếu nại', () => _complain(b)),
        if (b.status.isBeforePayment || b.canCancelPaid)
          outlined('Huỷ yêu cầu', () => _cancel(b)),
      ];
    }
    return [
      if (b.status == BookingStatus.active || b.status == BookingStatus.ended)
        if (b.deliveredDays < b.planDays)
          filled(
              'Soạn kế hoạch', Icons.edit_calendar_outlined, () => _compose(b)),
      if (b.canConfirmCompletion(now))
        filled('Xác nhận hoàn thành', Icons.task_alt_rounded,
            () => _confirmCompletion(b)),
      if (b.status == BookingStatus.disputed &&
          b.complaint?.chefResponse == null)
        filled('Phản hồi khiếu nại', Icons.gavel_rounded,
            () => _respondComplaint(b)),
      if (b.status.isBeforePayment) outlined('Không đồng ý', () => _decline(b)),
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
    if (b.isAdminResolved) {
      final note = b.escrow?.resolutionNote;
      return '${adminResolutionLine(b, party)}.'
          '${note == null || note.isEmpty ? '' : ' Ghi chú: "$note"'}';
    }
    return switch (b.status) {
      BookingStatus.requested => asChef
          ? 'Thành viên chờ bạn báo giá.'
          : 'Chuyên gia đang xem yêu cầu và sẽ báo giá trong chat.',
      BookingStatus.negotiating => open == null
          ? 'Đang trao đổi giá trong chat.'
          : open.proposedBy == party
              ? 'Đang chờ ${asChef ? 'thành viên' : 'chuyên gia'} trả lời đề xuất ${formatVnd(open.price)}.'
              : 'Bạn có đề xuất ${formatVnd(open.price)} chờ trả lời trong chat.',
      BookingStatus.awaitingPayment => b.contract == null
          ? null
          : asChef
              ? 'Chờ thành viên thanh toán trước ${formatVnStamp(b.contract!.paymentDueAt)}.'
              : 'Hai bên đã đồng ý ${formatVnd(b.contract!.price)}. Thanh toán trước ${formatVnStamp(b.contract!.paymentDueAt)}, nếu không yêu cầu sẽ hết hiệu lực.',
      BookingStatus.active => b.escrow == null ? null : _activeHint(b, asChef),
      BookingStatus.ended => b.escrow?.releaseAt == null
          ? null
          : '${b.autoCompleted ? '$autoCompletedNote.' : 'Hợp đồng đã hoàn thành.'} VeganLife giữ tiền đến ${formatVnStamp(b.escrow!.releaseAt!)}'
              '${asChef ? ', không có khiếu nại thì vào ví của bạn.' : ', có vấn đề thì bạn khiếu nại trước lúc đó.'}',
      BookingStatus.disputed => asChef
          ? (b.complaint?.chefResponse == null
              ? 'Thành viên đã khiếu nại. Hãy phản hồi để Ban quản trị xem xét.'
              : 'Ban quản trị đang xem xét khiếu nại.')
          : 'Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc.',
      BookingStatus.declined => asChef
          ? 'Bạn không đồng ý: ${b.declineReason ?? ''}. Thành viên không bị trừ tiền.'
          : 'Chuyên gia không đồng ý: ${b.declineReason ?? ''}. Bạn không bị trừ tiền, có thể đặt chuyên gia khác.',
      BookingStatus.cancelled => [
          'Đã huỷ: ${b.cancelReason ?? ''}'.trim(),
          if ((b.escrow?.refundedAmount ?? 0) > 0)
            '${formatVnd(b.escrow!.refundedAmount)} đã hoàn vào ví của thành viên.',
        ].join(' '),
      BookingStatus.expired => 'Quá hạn thanh toán.',
      BookingStatus.completed || BookingStatus.resolved => null,
    };
  }

  /// Paid, the contract not completed yet.
  String _activeHint(BookingDto b, bool asChef) {
    final price = formatVnd(b.escrow!.amount);
    final now = DateTime.now();
    final missing = b.planDays - b.deliveredDays;
    final reachedEnd = planReachedEnd(b.endDate, now);
    if (b.overdueUndelivered(now)) {
      const grace = BookingRules.autoCompleteDays;
      return asChef
          ? 'Đã quá $grace ngày sau ngày kết thúc mà còn $missing ngày chưa gửi nên hợp đồng không tự hoàn tất. Hãy gửi đủ rồi xác nhận; thành viên có thể khiếu nại.'
          : 'Đã quá $grace ngày sau ngày kết thúc mà chuyên gia còn $missing ngày chưa giao. VeganLife vẫn giữ tiền; bạn hãy gửi khiếu nại để Ban quản trị xử lý.';
    }
    if (b.deliveredAfterAutoComplete(now)) {
      final at = formatVnStamp(autoCompleteAt(b.endDate));
      return asChef
          ? 'Bạn gửi đủ sau $at nên hợp đồng không tự hoàn tất. Xác nhận hoàn thành để bắt đầu ${BookingRules.holdDays} ngày giữ tiền; nếu không, Ban quản trị sẽ xử lý.'
          : 'Chuyên gia gửi đủ sau $at nên hợp đồng không tự hoàn tất. VeganLife vẫn giữ $price đến khi chuyên gia xác nhận hoặc Ban quản trị xử lý; có vấn đề thì bạn khiếu nại nhé.';
    }
    if (missing > 0 && reachedEnd) {
      return asChef
          ? 'Kế hoạch đã đến ngày kết thúc mà còn $missing ngày chưa gửi. Hãy gửi đủ rồi xác nhận hoàn thành.'
          : 'Kế hoạch đã đến ngày kết thúc mà còn $missing ngày chưa giao. VeganLife vẫn giữ tiền; có vấn đề thì bạn khiếu nại nhé.';
    }
    if (asChef) {
      if (!b.fullyDelivered) {
        return 'VeganLife đang giữ $price. Gửi đủ các ngày rồi xác nhận hoàn thành từ ngày kết thúc kế hoạch (${formatDayMonth(b.endDate)}).';
      }
      return reachedEnd
          ? 'Bạn đã gửi đủ kế hoạch. Xác nhận hoàn thành để bắt đầu ${BookingRules.holdDays} ngày giữ tiền; nếu không, hệ thống tự hoàn tất lúc ${formatVnStamp(autoCompleteAt(b.endDate))}.'
          : 'Bạn đã gửi đủ kế hoạch. Xác nhận hoàn thành được từ ngày kết thúc kế hoạch (${formatDayMonth(b.endDate)}).';
    }
    return b.fullyDelivered && reachedEnd
        ? 'VeganLife đang giữ $price. Chuyên gia chưa xác nhận hoàn thành thì hệ thống tự hoàn tất lúc ${formatVnStamp(autoCompleteAt(b.endDate))}, sau đó tiền được giữ thêm ${BookingRules.holdDays} ngày.'
        : 'VeganLife đang giữ $price. Sau khi chuyên gia xác nhận hoàn thành, tiền được giữ thêm ${BookingRules.holdDays} ngày rồi mới chuyển cho chuyên gia.';
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
              flex: 3,
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
                  if (b.isFamily)
                    Text(
                      familySummary(b),
                      style: context.textStyles.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Wraps when long, at large text too, instead of squeezing the rest.
            Flexible(flex: 2, child: bookingStatusTag(context, b.status)),
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

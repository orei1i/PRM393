// lib/features/booking/data/mock/mock_booking_seeds.dart
//
// Seeds of [MockBookingDb], ported from the web console
// (FE/Web src/lib/mock_bookings.ts) so ids, people and amounts match:
// Minh Anh (u_me) — b_ma_tam_nego (Tâm, 10 ngày có phản hồi, chef offer
// 1.500.000đ open), b_ma_thuha_active (Thu Hà, 7 ngày giao một lần, paid,
// all days sent, day 3 is today), b_ma_tam_done (Tâm, 5 ngày, released).
// Lê Quang Tâm (u_chef_tam) — b_nam_tam_req (Hoàng Nam, Requested),
// b_vy_tam_active (Thảo Vy, today's day still a draft), b_tram_tam +
// cp_tram_tam (Ngọc Trâm, health_risk, 1 link + 1 image, Frozen),
// b_han_tam_done (Gia Hân, released). Tâm's wallet then reads: có thể rút
// 110.000đ (a 5.100.000đ withdrawal waits for an admin), đang giữ
// 1.134.000đ, tạm giữ 945.000đ. Dates are relative to "today" in
// Asia/Ho_Chi_Minh, so the seeds keep their meaning on any day.
part of 'mock_booking_db.dart';

typedef _Dish = (String id, String name, int kcal);

/// Chef recipes used to fill plan days (no peanut, sesame or grapefruit
/// unless a seed overrides it). Same pools as the web mock.
const _dishes = <MealSlot, List<_Dish>>{
  MealSlot.breakfast: [
    ('rc_xoi_dau_xanh', 'Xôi đậu xanh nước cốt dừa', 380),
    ('rc_banh_mi_nam', 'Bánh mì chay pate nấm', 420),
    ('rc_yen_mach_chuoi', 'Yến mạch sữa đậu nành chuối', 350),
    ('rc_pho_chay', 'Phở chay nấm hương', 450),
    ('rc_chao_bi_do', 'Cháo yến mạch bí đỏ', 300),
  ],
  MealSlot.snackAm: [
    ('rc_sua_hat_dieu', 'Sữa hạt điều', 160),
    ('rc_trai_cay', 'Đĩa trái cây theo mùa', 120),
  ],
  MealSlot.lunch: [
    ('rc_com_dau_hu_sot_ca', 'Cơm gạo lứt đậu hũ sốt cà', 620),
    ('rc_bun_rieu_chay', 'Bún riêu chay', 540),
    ('rc_com_tam_chay', 'Cơm tấm chay sườn đậu', 650),
    ('rc_mi_quang_chay', 'Mì Quảng chay', 580),
    ('rc_bun_xao_nam', 'Bún xào rau củ nấm', 520),
  ],
  MealSlot.snackPm: [
    ('rc_che_dau_den', 'Chè đậu đen ít đường', 180),
    ('rc_sua_chua_dua', 'Sữa chua dừa hạt chia', 150),
    ('rc_khoai_lang', 'Khoai lang luộc', 130),
  ],
  MealSlot.dinner: [
    ('rc_lau_nam', 'Lẩu nấm chay', 480),
    ('rc_dau_hu_sot_ca', 'Đậu hũ sốt cà chua + cơm', 520),
    ('rc_canh_rong_bien', 'Canh rong biển đậu hũ non + cơm', 450),
    ('rc_rau_cu_xao_nam', 'Rau củ xào nấm đùi gà + gạo lứt', 510),
    ('rc_ca_ri_chay', 'Cà ri chay khoai lang', 560),
  ],
  MealSlot.snackLate: [
    ('rc_sua_dau_nanh', 'Sữa đậu nành ấm', 130),
    ('rc_chuoi_hap', 'Chuối hấp nước cốt dừa', 140),
  ],
};

const _feedback = <(int, Adherence, String)>[
  (5, Adherence.all, 'Bữa sáng làm kịp trong 10 phút, rất ổn.'),
  (
    4,
    Adherence.partly,
    'Mình đổi bữa trưa vì đi công tác, phần còn lại làm đủ.'
  ),
  (4, Adherence.all, 'Món canh hơi nhạt, còn lại ngon.'),
  (3, Adherence.partly, 'Hôm nay bận nên chỉ làm được bữa tối.'),
  (5, Adherence.all, 'Rất hợp khẩu vị, cả nhà ăn hết.'),
  (4, Adherence.none, 'Ăn cỗ cưới nên không theo được, mai làm lại.'),
];

/// Members of the seeds: (name, email).
const _members = <String, (String, String)>{
  'u_me': ('Minh Anh', 'minhanh.nguyen@gmail.com'),
  'u_hoang_nam': ('Hoàng Nam', 'hoangnam.dev@gmail.com'),
  'u_thao_vy': ('Thảo Vy', 'thaovy.nguyen@gmail.com'),
  'u_ngoc_tram': ('Ngọc Trâm', 'ngoctram.k17@gmail.com'),
  'u_gia_han': ('Gia Hân', 'giahan.tran@gmail.com'),
};

/// Shared health profiles (what the chef sees with "Chia sẻ hồ sơ sức khoẻ").
Map<String, dynamic>? _healthOf(String memberId) => switch (memberId) {
      // Same as Minh Anh's planner health profile (P4 mock).
      'u_me' => MockBookingDb.memberHealthJson(const HealthProfile(
          heightCm: 172,
          weightKg: 66,
          bmi: 22.3,
          goal: HealthGoal.leanMuscle,
          gender: Gender.female,
          birthYear: 1997,
          activityLevel: ActivityLevel.light,
          allergies: ['peanut'],
        )),
      'u_hoang_nam' => {
          'heightCm': 175,
          'weightKg': 68,
          'bmi': 22.2,
          'gender': 'Male',
          'age': 26,
          'activityLevel': 'active',
          'dailyKcalTarget': 2900,
        },
      'u_thao_vy' => {
          'heightCm': 158,
          'weightKg': 50,
          'bmi': 20.0,
          'gender': 'Female',
          'age': 22,
          'activityLevel': 'light',
          'dailyKcalTarget': 1650,
        },
      'u_ngoc_tram' => {
          'heightCm': 160,
          'weightKg': 56,
          'bmi': 21.9,
          'gender': 'Female',
          'age': 41,
          'activityLevel': 'sedentary',
          'dailyKcalTarget': 1500,
        },
      'u_gia_han' => {
          'heightCm': 162,
          'weightKg': 54,
          'bmi': 20.6,
          'gender': 'Female',
          'age': 34,
          'activityLevel': 'moderate',
          'dailyKcalTarget': 1900,
        },
      _ => null,
    };

class _ComplaintSeed {
  const _ComplaintSeed({
    required this.id,
    required this.reason,
    required this.description,
    required this.outcome,
    required this.at,
    required this.evidence,
    this.amount,
    this.chefResponse,
  });

  final String id;
  final ComplaintReason reason;
  final String description;
  final RequestedOutcome outcome;

  /// PartialRefund only.
  final int? amount;
  final DateTime at;
  final List<(EvidenceKind, String, String?)> evidence;

  /// (text, minutes after the complaint).
  final (String, int)? chefResponse;
}

class _MealOverride {
  const _MealOverride(this.name, this.kcal, [this.note]);

  final String name;
  final int kcal;
  final String? note;
}

class _Seed {
  const _Seed({
    required this.id,
    required this.member,
    required this.chef,
    required this.type,
    required this.days,
    required this.start,
    required this.status,
    required this.goal,
    required this.allergies,
    required this.pattern,
    required this.budget,
    required this.needs,
    required this.created,
    this.offers = const [],
    this.chat = const [],
    this.orderId,
    this.todayDraft = false,
    this.feedbackOverrides = const {},
    this.overrides = const {},
    this.dayNotes = const {},
    this.complaint,
  });

  final String id;
  final String member;
  final String chef;
  final BookingType type;
  final int days;

  /// Start date, days from today (VN).
  final int start;

  /// Seeded status; the lazy rules may move it on read.
  final BookingStatus status;
  final String goal;
  final List<String> allergies;
  final List<MealSlot> pattern;
  final int? budget;
  final String needs;
  final DateTime created;

  /// (by, price, note, minutes after the request); the last one is Open
  /// (no contract) or Accepted.
  final List<(BookingParty, int, String, int)> offers;

  /// (by, minutes after the request, text).
  final List<(BookingParty, int, String)> chat;
  final String? orderId;

  /// DailyFeedback: today's day is still a draft.
  final bool todayDraft;
  final Map<int, (int, Adherence, String)> feedbackOverrides;

  /// "4:breakfast" → a specific dish for that day and slot.
  final Map<String, _MealOverride> overrides;
  final Map<int, String> dayNotes;
  final _ComplaintSeed? complaint;
}

const _maNeeds =
    'Mình muốn giảm khoảng 3 kg trong tháng, bữa sáng cần làm nhanh dưới 15 phút vì đi làm sớm. '
    'Dị ứng đậu phộng, không ăn được hành sống.';

int _hash(String s) => s.codeUnits.fold(0, (sum, c) => sum + c);

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

void _seedBookings(MockBookingDb db) {
  final now = db.now;
  final today = db.today;
  DateTime atVn(int offset, int hour, int minute) =>
      vnTime(addDays(today, offset), hour, minute);
  const h = Duration(hours: 1);

  final seeds = [
    // ------------------------------------------------ Minh Anh (u_me)
    _Seed(
      id: 'b_ma_tam_nego',
      member: 'u_me',
      chef: 'u_chef_tam',
      type: BookingType.dailyFeedback,
      days: 10,
      start: 3,
      status: BookingStatus.negotiating,
      goal: 'lose_weight',
      allergies: const ['peanut'],
      pattern: const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      budget: 80000,
      needs: _maNeeds,
      created: now.subtract(h * 26),
      chat: const [
        (
          BookingParty.chef,
          50,
          'Chào Minh Anh, mình đọc hồ sơ rồi. Bạn ăn được nấm và đậu hũ hằng ngày không, hay cần đổi bớt?'
        ),
        (
          BookingParty.member,
          95,
          'Mình ăn được hết nha anh, chỉ cần tránh đậu phộng thôi.'
        ),
      ],
      offers: const [
        (
          BookingParty.chef,
          1500000,
          '10 ngày có phản hồi mỗi ngày: mình điều chỉnh thực đơn theo góp ý mỗi tối. '
              'Giá đã gồm danh sách đi chợ theo tuần.',
          140
        ),
      ],
    ),
    _Seed(
      id: 'b_ma_thuha_active',
      member: 'u_me',
      chef: 'u_thu_ha',
      type: BookingType.oneShot,
      days: 7,
      start: -2,
      status: BookingStatus.active,
      goal: 'lose_weight',
      allergies: const ['peanut'],
      pattern: const [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.snackPm,
        MealSlot.dinner,
      ],
      budget: 70000,
      needs:
          'Cần thực đơn 7 ngày giảm cân lành mạnh khoảng 1.600 kcal/ngày, bữa sáng dưới 15 phút, '
          'có bữa phụ chiều vì mình hay đói lúc 4 giờ. Dị ứng đậu phộng.',
      created: atVn(-6, 8, 40),
      offers: const [
        (
          BookingParty.chef,
          840000,
          '7 ngày × 120.000đ, giao trọn kế hoạch trước ngày bắt đầu, kèm bảng kcal từng bữa.',
          180
        ),
      ],
      chat: const [
        (BookingParty.member, 265, 'Dạ em đồng ý ạ, em thanh toán luôn.'),
      ],
      orderId: 'ord_601',
      dayNotes: const {
        1: 'Uống đủ 2 lít nước, bữa phụ chiều có thể đổi sang 1 quả táo.',
        3: 'Hôm nay nhiều rau xanh, nhớ chuẩn bị canh từ tối hôm trước.',
      },
    ),
    _Seed(
      id: 'b_ma_tam_done',
      member: 'u_me',
      chef: 'u_chef_tam',
      type: BookingType.dailyFeedback,
      days: 5,
      start: -9,
      status: BookingStatus.completed,
      goal: 'eat_clean',
      allergies: const ['peanut'],
      pattern: const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      budget: 60000,
      needs:
          'Thử ăn chay 5 ngày cho quen, món dễ nấu trong bếp nhỏ ở chung cư, không dùng lò nướng.',
      created: atVn(-13, 19, 10),
      offers: const [
        (
          BookingParty.chef,
          900000,
          '5 ngày có phản hồi mỗi ngày, 180.000đ/ngày.',
          60
        ),
      ],
      orderId: 'ord_602',
    ),
    // ------------------------------------------------ Lê Quang Tâm (u_chef_tam)
    _Seed(
      id: 'b_nam_tam_req',
      member: 'u_hoang_nam',
      chef: 'u_chef_tam',
      type: BookingType.oneShot,
      days: 14,
      start: 5,
      status: BookingStatus.requested,
      goal: 'gain_muscle',
      allergies: const [],
      pattern: const [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.snackPm,
        MealSlot.dinner,
      ],
      budget: 100000,
      needs:
          'Mình tập gym 4 buổi/tuần, cần thực đơn chay 14 ngày đủ đạm (khoảng 120 g/ngày), '
          'ưu tiên món nấu sẵn được cho 2 ngày.',
      created: now.subtract(h * 3),
    ),
    _Seed(
      id: 'b_vy_tam_active',
      member: 'u_thao_vy',
      chef: 'u_chef_tam',
      type: BookingType.dailyFeedback,
      days: 7,
      start: -2,
      status: BookingStatus.active,
      goal: 'eat_clean',
      allergies: const [],
      pattern: const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      budget: 90000,
      needs: 'Muốn ăn chay thanh đạm 7 ngày sau Tết, ít dầu mỡ, nhiều canh. '
          'Mỗi tối mình sẽ góp ý để anh chỉnh ngày hôm sau.',
      created: atVn(-5, 10, 5),
      offers: const [
        (
          BookingParty.chef,
          1400000,
          '7 ngày có phản hồi mỗi ngày, 200.000đ/ngày vì có thêm canh mỗi bữa.',
          70
        ),
        (
          BookingParty.member,
          1200000,
          'Anh giảm giúp em chút được không ạ, em sinh viên.',
          130
        ),
        (
          BookingParty.chef,
          1260000,
          'Mình để 180.000đ/ngày như giá niêm yết nhé.',
          190
        ),
      ],
      orderId: 'ord_603',
      todayDraft: true,
      feedbackOverrides: const {
        2: (
          4,
          Adherence.partly,
          'Bữa tối hơi nhiều dầu, mai anh cho em món hấp nhé.'
        ),
      },
    ),
    _Seed(
      id: 'b_tram_tam',
      member: 'u_ngoc_tram',
      chef: 'u_chef_tam',
      type: BookingType.oneShot,
      days: 7,
      start: -7,
      status: BookingStatus.disputed,
      goal: 'eat_clean',
      allergies: const ['peanut'],
      pattern: const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      budget: 90000,
      needs:
          'Mình đang uống thuốc huyết áp (nhóm chẹn kênh canxi) theo đơn bác sĩ, cần thực đơn ít muối '
          'và tránh hoàn toàn bưởi, nước ép bưởi. Ưu tiên món dễ nấu sau giờ làm.',
      created: atVn(-12, 9, 15),
      offers: const [
        (
          BookingParty.chef,
          1050000,
          '7 ngày × 150.000đ, giao trọn kế hoạch trước ngày bắt đầu, ít muối theo yêu cầu.',
          120
        ),
      ],
      orderId: 'ord_604',
      overrides: const {
        '4:breakfast': _MealOverride('Gỏi bưởi chay + nước ép bưởi', 280,
            'Có thể thay bưởi bằng cam nếu đang dùng thuốc.'),
        '6:breakfast': _MealOverride('Sinh tố bưởi hồng chuối', 260),
      },
      complaint: _ComplaintSeed(
        id: 'cp_tram_tam',
        reason: ComplaintReason.healthRisk,
        description:
            'Ngày 4 và ngày 6 có gỏi bưởi, nước ép bưởi và sinh tố bưởi dù mình đã ghi rõ đang dùng '
            'thuốc huyết áp và cần tránh bưởi. Bưởi có thể làm tăng nồng độ một số thuốc huyết áp '
            'trong máu. Mình phải tự đổi món 2 ngày đó.',
        outcome: RequestedOutcome.partialRefund,
        amount: 500000,
        at: now.subtract(h * 5),
        evidence: const [
          (
            EvidenceKind.link,
            'https://www.fda.gov/consumers/consumer-updates/grapefruit-juice-and-some-drugs-dont-mix',
            'FDA: Nước ép bưởi và một số loại thuốc không nên dùng chung',
          ),
          (
            EvidenceKind.image,
            'https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_tram_tam_ngay4.jpg',
            'Ảnh chụp kế hoạch ngày 4',
          ),
        ],
        chefResponse: (
          'Ở ngày 4 tôi có ghi chú thay bưởi bằng cam nếu đang dùng thuốc, nhưng đồng ý là nên bỏ '
              'hẳn vì chị đã khai từ đầu. Ngày 6 là sơ suất của tôi. Tôi đồng ý hoàn 300.000đ cho 2 '
              'ngày bị ảnh hưởng.',
          180
        ),
      ),
    ),
    _Seed(
      id: 'b_han_tam_done',
      member: 'u_gia_han',
      chef: 'u_chef_tam',
      type: BookingType.dailyFeedback,
      days: 30,
      start: -53,
      status: BookingStatus.completed,
      goal: 'maintain',
      allergies: const [],
      pattern: const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      budget: 250000,
      needs:
          'Thực đơn chay 30 ngày cho cả gia đình 4 người (2 bé tiểu học), mỗi tối mình góp ý để anh '
          'chỉnh. Cần danh sách đi chợ theo tuần.',
      created: atVn(-58, 20, 30),
      offers: const [
        (
          BookingParty.chef,
          6000000,
          'Thực đơn cho 4 người, 200.000đ/ngày, có phản hồi mỗi ngày.',
          90
        ),
        (BookingParty.member, 5500000, 'Anh xem bớt chút được không ạ?', 300),
        (
          BookingParty.chef,
          6000000,
          'Mình giữ 6.000.000đ nhưng tặng thêm danh sách đi chợ theo tuần và món ăn vặt cho bé.',
          420
        ),
      ],
      orderId: 'ord_605',
    ),
  ];

  for (final seed in seeds) {
    _build(db, seed, atVn);
  }
  for (final row in db.bookings) {
    // Events "in the future" of the seed clock are dropped; oldest first.
    row.messages
      ..removeWhere((m) => m.createdAt.isAfter(now))
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final (i, m) in row.messages.indexed) {
      m.id = 'msg_${row.id}_${i + 1}';
    }
  }
}

void _build(MockBookingDb db, _Seed seed,
    DateTime Function(int offset, int hour, int minute) atVn) {
  final commerce = db.commerce;
  final chef = commerce.chef(seed.chef);
  final (memberName, memberEmail) = _members[seed.member]!;
  final startDate = addDays(db.today, seed.start);
  const minute = Duration(minutes: 1);
  final row = MockBookingRow(
    id: seed.id,
    memberId: seed.member,
    memberName: memberName,
    memberEmail: memberEmail,
    chefId: chef.id,
    chefUserId: chef.userId,
    chefName: chef.fullName,
    chefEmail: chef.email,
    bookingType: seed.type,
    planDays: seed.days,
    startDate: startDate,
    goal: seed.goal,
    allergies: [...seed.allergies],
    mealPattern: [...seed.pattern],
    budgetPerDay: seed.budget,
    needs: seed.needs,
    shareHealthProfile: true,
    status: seed.status,
    createdAt: seed.created,
    memberHealth: _healthOf(seed.member),
  );
  db.bookings.add(row);
  db.say(
      row,
      BookingParty.system,
      '$memberName đã gửi yêu cầu thiết kế thực đơn ${seed.days} ngày '
      '(${seed.type.label.toLowerCase()}), bắt đầu ${formatDayMonth(startDate)}.',
      at: seed.created);
  db.say(row, BookingParty.member, seed.needs, at: seed.created.add(minute));
  for (final (by, after, text) in seed.chat) {
    db.say(row, by, text, at: seed.created.add(minute * after));
  }

  final offers = seed.offers;
  final hasContract = offers.isNotEmpty &&
      seed.status != BookingStatus.requested &&
      seed.status != BookingStatus.negotiating &&
      seed.status != BookingStatus.declined;
  final lastOfferAt =
      offers.isEmpty ? seed.created : seed.created.add(minute * offers.last.$4);
  final contractAt = lastOfferAt.add(minute * 90);
  for (final (i, (by, price, note, after)) in offers.indexed) {
    final last = i == offers.length - 1;
    final createdAt = seed.created.add(minute * after);
    final offer = MockOfferRow(
      id: 'of_${seed.id}_${i + 1}',
      proposedBy: by,
      price: price,
      planDays: seed.days,
      bookingType: seed.type,
      startDate: startDate,
      note: note,
      createdAt: createdAt,
      status: !last
          ? OfferStatus.superseded
          : hasContract
              ? OfferStatus.accepted
              : OfferStatus.open,
    )..respondedAt = !last
        ? seed.created.add(minute * offers[i + 1].$4)
        : hasContract
            ? contractAt
            : null;
    row
      ..offers.add(offer)
      ..updatedAt = createdAt;
    db.say(row, by, note, at: createdAt, offer: offer);
  }
  if (!hasContract) return;

  final accepted = row.offers.last;
  final price = accepted.price;
  final acceptor =
      accepted.proposedBy == BookingParty.chef ? memberName : chef.fullName;
  final paymentDueAt = contractAt.add(BookingRules.paymentWindow);
  final qrAt = contractAt.add(minute * 40);
  final paidAt = qrAt.add(minute * 2);
  db._contract(row, accepted, contractAt, paymentDueAt);
  row.updatedAt = contractAt;
  db.say(
      row,
      BookingParty.system,
      '$acceptor đã đồng ý đề xuất ${formatVnd(price)}. Hồ sơ hợp đồng đã được '
      'tạo — thanh toán trước ${formatVnStamp(paymentDueAt)}.',
      at: contractAt);

  final order = MockOrderRow(
    id: seed.orderId!,
    userId: seed.member,
    buyerName: memberName,
    bookingId: seed.id,
    chefId: chef.id,
    chefName: chef.fullName,
    amount: price,
    createdAt: contractAt,
    status: OrderStatus.paid,
  );
  commerce.orders.add(order);
  row.orderId = order.id;
  final payment = MockPaymentRow(
    id: 'pay_${order.id}',
    orderId: order.id,
    transactionRef: commerce.nextRef(qrAt),
    amount: price,
    createdAt: qrAt,
    expiresAt: qrAt.add(MockCommerceDb.paymentTtl),
  )
    ..status = PaymentStatus.paid
    ..paidAt = paidAt;
  commerce.payments.add(payment);
  db._fund(row, payment, paidAt);
  _buildDays(db, seed, row, paidAt, row.contract!.deliveryDueAt, atVn);
  if (seed.complaint case final c?) _buildComplaint(db, row, c);
  if (seed.status == BookingStatus.completed) db._autoRelease(row);
}

void _buildDays(
  MockBookingDb db,
  _Seed seed,
  MockBookingRow row,
  DateTime paidAt,
  DateTime dueAt,
  DateTime Function(int offset, int hour, int minute) atVn,
) {
  final now = db.now;
  final oneShot = seed.type == BookingType.oneShot;
  final oneShotSentAt = _max(paidAt.add(const Duration(hours: 2)),
      dueAt.subtract(const Duration(hours: 6)));
  final byDate = [
    for (var i = 0; i < seed.days; i++) seed.start + i,
  ].where((o) => o < 0 || (o == 0 && !seed.todayDraft)).length;
  final delivered =
      oneShot ? (oneShotSentAt.isAfter(now) ? 0 : seed.days) : byDate;
  final h = _hash(seed.id);

  for (final day in row.days) {
    final i = day.dayIndex;
    final offset = seed.start + i - 1;
    DateTime? sentAt;
    if (i <= delivered) {
      sentAt = oneShot
          ? oneShotSentAt
          : _max(
              paidAt.add(const Duration(hours: 1)), atVn(offset - 1, 20, 30));
    }
    final sent = sentAt != null && !sentAt.isAfter(now);
    final draft = !sent && offset == 0 && seed.todayDraft;
    final (rating, adherence, body) =
        seed.feedbackOverrides[i] ?? _feedback[(i + h) % _feedback.length];
    final feedbackAt = atVn(offset, 20, 0);
    if (sent) {
      day
        ..status = PlanDayStatus.sent
        ..sentAt = sentAt
        ..chefNote = seed.dayNotes[i]
        ..meals = _mealsFor(seed, i, partial: false);
    } else if (draft) {
      day
        ..status = PlanDayStatus.draft
        ..meals = _mealsFor(seed, i, partial: true);
    }
    if (!oneShot && sent) {
      if (!feedbackAt.isAfter(now)) {
        day.feedback = DayFeedbackDto(
            rating: rating,
            adherence: adherence,
            body: body,
            createdAt: feedbackAt);
      }
      db.say(row, BookingParty.system,
          '${row.chefName} đã gửi kế hoạch ngày $i (${formatDayMonth(day.date)}).',
          at: sentAt);
      if (!feedbackAt.isAfter(now)) {
        db.say(row, BookingParty.system,
            '${row.memberName} đã phản hồi ngày $i: $rating★ · $body',
            at: feedbackAt);
      }
    }
  }
  if (oneShot && delivered > 0) {
    db.say(
        row,
        BookingParty.chef,
        'Mình đã gửi toàn bộ kế hoạch ${seed.days} ngày, bạn xem tab Kế hoạch nhé. '
        'Có gì chưa rõ cứ nhắn mình.',
        at: oneShotSentAt);
  }
}

List<PlanMealDto> _mealsFor(_Seed seed, int dayIndex, {required bool partial}) {
  final slots = partial
      ? seed.pattern.sublist(0, (seed.pattern.length - 1).clamp(1, 6))
      : seed.pattern;
  final h = _hash(seed.id);
  return [
    for (final (k, slot) in slots.indexed)
      if (seed.overrides['$dayIndex:${slot.apiValue}'] case final o?)
        PlanMealDto(
          slot: slot,
          recipe: PlanRecipeDto(
              id: 'rc_${seed.id}_${dayIndex}_${slot.apiValue}',
              name: o.name,
              calories: o.kcal),
          note: o.note,
        )
      else
        () {
          final pool = _dishes[slot]!;
          final (id, name, kcal) = pool[(dayIndex + k + h) % pool.length];
          return PlanMealDto(
              slot: slot,
              recipe: PlanRecipeDto(id: id, name: name, calories: kcal));
        }(),
  ];
}

void _buildComplaint(MockBookingDb db, MockBookingRow row, _ComplaintSeed c) {
  final price = row.contract!.price;
  final complaint = MockComplaintRow(
    id: c.id,
    bookingId: row.id,
    reason: c.reason,
    description: c.description,
    requestedOutcome: c.outcome,
    requestedAmount:
        c.outcome == RequestedOutcome.fullRefund ? price : (c.amount ?? 0),
    createdAt: c.at,
  );
  for (final (i, (kind, url, caption)) in c.evidence.indexed) {
    complaint.evidence.add(MockEvidenceRow(
      id: 'ev_${c.id}_${i + 1}',
      kind: kind,
      url: url,
      caption: caption,
      submittedBy: BookingParty.member,
      createdAt: c.at,
    ));
  }
  final response = c.chefResponse;
  if (response != null) {
    complaint
      ..chefResponse = response.$1
      ..chefRespondedAt = c.at.add(Duration(minutes: response.$2));
  }
  row
    ..complaint = complaint
    ..status = BookingStatus.disputed
    ..updatedAt = c.at;
  row.escrow!.status = EscrowStatus.frozen;
  db.say(
      row,
      BookingParty.system,
      '${row.memberName} đã gửi khiếu nại: "${c.reason.label}". '
      'Tiền được tạm giữ đến khi Ban quản trị quyết định.',
      at: c.at);
  if (response != null) {
    db.say(row, BookingParty.chef, response.$1, at: complaint.chefRespondedAt);
  }
}

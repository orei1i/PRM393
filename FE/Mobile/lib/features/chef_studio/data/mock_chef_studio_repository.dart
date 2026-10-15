// lib/features/chef_studio/data/mock_chef_studio_repository.dart
import '../../../core/session/user_role.dart';
import '../../../core/utils/mock_delay.dart';
import '../../chef/data/models/service_model.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../../commerce/data/models/consultation_model.dart';
import '../../commerce/data/models/order_model.dart';
import '../../commerce/domain/commerce_status.dart';
import '../domain/chef_studio_rules.dart';
import 'chef_studio_api_service.dart';
import 'models/chef_studio_models.dart';

/// Chef side of [MockCommerceDb]. "Me" is the chef profile whose `userId` is
/// the signed-in user. Errors: `#fail` in a title, reason or notes → 503;
/// starting too early → 409 `too_early`; notes under 20 chars → 400;
/// deleting a service with orders → 409; not a chef → 403.
class MockChefStudioRepository implements ChefStudioApiService {
  MockChefStudioRepository({
    required this.currentUserId,
    required this.currentUserName,
    required this.currentRole,
  });

  final String? Function() currentUserId;
  final String Function() currentUserName;
  final UserRole Function() currentRole;

  MockCommerceDb get _db => MockCommerceDb.instance;

  String _chefUserId() {
    final id = currentUserId();
    if (id == null) throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.');
    if (currentRole() != UserRole.chef) {
      throw mockError(403, 'Chỉ dành cho chuyên gia.', 'not_chef');
    }
    return id;
  }

  MockChefRow _chef() =>
      _db.chefOfUser(_chefUserId()) ??
      (throw mockError(
          404, 'Bạn chưa có hồ sơ chuyên gia.', 'chef_profile_missing'));

  MockServiceRow _myService(String id) {
    final chef = _chef();
    final s = _db.service(id);
    if (s.chefId != chef.id) throw mockError(404, 'Không tìm thấy dịch vụ.');
    return s;
  }

  MockConsultationRow _myConsultation(String id) {
    final chef = _chef();
    final c = _db.consultation(id);
    if (c.order.chefId != chef.id ||
        c.status == ConsultationStatus.awaitingPayment) {
      throw mockError(404, 'Không tìm thấy lịch hẹn.');
    }
    return c;
  }

  static void _check(String? error) {
    if (error != null) throw mockError(400, error, 'validation');
  }

  static void _expect(MockConsultationRow c, ConsultationStatus status) {
    if (c.status != status) {
      throw mockError(
          409,
          'Lịch hẹn đang ở trạng thái "${c.status.label}", không thực hiện được thao tác này.',
          'invalid_status');
    }
  }

  ChefProfileDto _profile(MockChefRow c) => ChefProfileDto.fromJson({
        'id': c.id,
        'userId': c.userId,
        'specialty': c.specialties.firstOrNull ?? '',
        'bio': c.bio,
      });

  ConsultationDto _consultation(MockConsultationRow c) =>
      ConsultationDto.fromJson(_db.consultationJson(c));

  ServiceDto _service(MockServiceRow s) =>
      ServiceDto.fromJson(s.toJson(withContentUrl: true));

  @override
  Future<ChefProfileDto> getMyProfile() async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) {
      throw mockError(
          404, 'Bạn chưa có hồ sơ chuyên gia.', 'chef_profile_missing');
    }
    return _profile(chef);
  }

  @override
  Future<ChefProfileDto> updateMyProfile(ChefProfileRequestDto request) async {
    await mockDelay(700);
    final userId = _chefUserId();
    if (hasFailTrigger(request.bio)) {
      throw mockError(503, 'Máy chủ đang bận, chưa lưu được hồ sơ.');
    }
    _check(ChefProfileRules.specialty(request.specialty));
    _check(ChefProfileRules.bio(request.bio));
    final existing = _db.chefOfUser(userId);
    if (existing != null) {
      // SQL keeps a single `specialty`.
      existing
        ..specialties = [request.specialty]
        ..bio = request.bio.trim();
      return _profile(existing);
    }
    final created = MockChefRow.created(
      id: 'chef_$userId',
      userId: userId,
      fullName: currentUserName(),
      specialty: request.specialty,
      bio: request.bio.trim(),
    );
    _db.chefs.add(created);
    return _profile(created);
  }

  @override
  Future<List<ServiceDto>> myServices() async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    return _db.servicesOf(chef.id).map(_service).toList();
  }

  void _validate(ServiceRequestDto r) {
    _check(ServiceRules.title(r.title));
    _check(ServiceRules.price(r.price));
    _check(ServiceRules.minutes(r.type, r.durationMinutes));
    _check(ServiceRules.description(r.description ?? ''));
    _check(ServiceRules.contentUrl(r.type, r.contentUrl ?? ''));
  }

  void _apply(MockServiceRow s, ServiceRequestDto r) {
    final description = r.description?.trim() ?? '';
    s
      ..title = r.title.trim()
      ..type = r.type
      ..price = r.price
      ..description = description
      ..durationMinutes = r.type.isPackage ? null : r.durationMinutes
      ..contentUrl = r.type.isPackage ? r.contentUrl?.trim() : null;
  }

  @override
  Future<ServiceDto> createService(ServiceRequestDto request) async {
    await mockDelay(700);
    final chef = _chef();
    if (hasFailTrigger(request.title)) {
      throw mockError(503, 'Máy chủ đang bận, chưa lưu được dịch vụ.');
    }
    _validate(request);
    final row = MockServiceRow(
      id: _db.newId('svc'),
      chefId: chef.id,
      title: '',
      type: request.type,
      price: 0,
    );
    _apply(row, request);
    _db.services.add(row);
    return _service(row);
  }

  @override
  Future<ServiceDto> updateService(String id, ServiceRequestDto request) async {
    await mockDelay(700);
    final row = _myService(id);
    if (hasFailTrigger(request.title)) {
      throw mockError(503, 'Máy chủ đang bận, chưa lưu được dịch vụ.');
    }
    _validate(request);
    _apply(row, request);
    return _service(row);
  }

  @override
  Future<void> deleteService(String id) async {
    await mockDelay(600);
    final row = _myService(id);
    final hasOrders = _db.orders
        .any((o) => o.serviceId == id && o.status != OrderStatus.cancelled);
    if (hasOrders) {
      throw mockError(409, 'Dịch vụ đã có đơn hàng nên không xoá được.',
          'service_has_orders');
    }
    _db.services.remove(row);
  }

  @override
  Future<List<OrderDto>> myOrders({OrderStatus? status}) async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    final list = _db.orders
        .where((o) =>
            o.chefId == chef.id && (status == null || o.status == status))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list
        .map((o) => OrderDto.fromJson(_db.orderJson(o, withBuyer: true)))
        .toList();
  }

  @override
  Future<List<ConsultationDto>> myConsultations(
      {ConsultationStatus? status}) async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    final list = _db.consultations
        .where((c) =>
            c.order.chefId == chef.id &&
            c.status != ConsultationStatus.awaitingPayment &&
            (status == null || c.status == status))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list.map(_consultation).toList();
  }

  @override
  Future<ConsultationDto> confirmConsultation(String id) async {
    await mockDelay(500);
    final c = _myConsultation(id);
    _expect(c, ConsultationStatus.pending);
    c.status = ConsultationStatus.confirmed;
    return _consultation(c);
  }

  @override
  Future<ConsultationDto> declineConsultation(String id, String reason) async {
    await mockDelay(600);
    final c = _myConsultation(id);
    if (hasFailTrigger(reason)) {
      throw mockError(503, 'Máy chủ đang bận, chưa gửi được phản hồi.');
    }
    _check(ConsultationRules.declineReason(reason));
    _expect(c, ConsultationStatus.pending);
    c
      ..status = ConsultationStatus.declined
      ..declineReason = reason.trim();
    _db.refund(c.order);
    return _consultation(c);
  }

  @override
  Future<ConsultationDto> startConsultation(String id) async {
    await mockDelay(500);
    final c = _myConsultation(id);
    _expect(c, ConsultationStatus.confirmed);
    if (!ConsultationRules.canStart(c.startAt, _db.now)) {
      throw mockError(
          409, 'Chỉ bắt đầu được trước giờ hẹn 15 phút.', 'too_early');
    }
    c
      ..status = ConsultationStatus.inProgress
      ..startedAt = _db.now;
    return _consultation(c);
  }

  @override
  Future<ConsultationDto> completeConsultation(String id, String notes) async {
    await mockDelay(600);
    final c = _myConsultation(id);
    if (hasFailTrigger(notes)) {
      throw mockError(503, 'Máy chủ đang bận, chưa lưu được ghi chú.');
    }
    _check(ConsultationRules.notes(notes));
    _expect(c, ConsultationStatus.inProgress);
    c
      ..status = ConsultationStatus.completed
      ..chefNotes = notes.trim()
      ..completedAt = _db.now;
    return _consultation(c);
  }

  KnowledgeDocDto _doc(MockDocRow d) => KnowledgeDocDto.fromJson({
        'id': d.id,
        'chefId': d.chefId,
        'title': d.title,
        'source': 'Chef',
        'fileUrl': d.fileUrl,
        'createdAt': d.createdAt.toUtc().toIso8601String(),
        'status': d.status,
        'reviewNote': d.reviewNote,
        'chunkCount': d.chunkCount,
      });

  @override
  Future<List<KnowledgeDocDto>> myKnowledgeDocs() async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    final list = _db.docs.where((d) => d.chefId == chef.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.map(_doc).toList();
  }

  @override
  Future<KnowledgeDocDto> submitKnowledgeDoc(
      KnowledgeDocRequestDto request) async {
    await mockDelay(800);
    final chef = _chef();
    if (hasFailTrigger(request.title)) {
      throw mockError(503, 'Máy chủ đang bận, chưa gửi được tài liệu.');
    }
    _check(KnowledgeDocRules.title(request.title));
    _check(KnowledgeDocRules.fileUrl(request.fileUrl));
    final row = MockDocRow(
      id: _db.newId('kd'),
      chefId: chef.id,
      title: request.title.trim(),
      fileUrl: request.fileUrl.trim(),
      createdAt: _db.now,
    );
    _db.docs.add(row);
    return _doc(row);
  }
}

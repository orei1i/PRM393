// lib/features/chef/data/mock_chef_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import 'chef_api_service.dart';
import 'mock/chef_mock_data.dart';
import 'models/chef_model.dart';

class MockChefRepository implements ChefApiService {
  static final _db = _MockChefDb();

  @override
  Future<List<ChefDto>> listChefs({String? query, String? specialty}) async {
    await mockDelay(600);
    return _db.chefs.where((c) {
      final bySpecialty =
          specialty == null || c.specialties.contains(specialty);
      final byQuery = query == null ||
          query.trim().isEmpty ||
          matchesQuery(
              '${c.fullName} ${c.headline} ${c.specialties.join(' ')} ${c.city}',
              query);
      return bySpecialty && byQuery;
    }).toList();
  }

  @override
  Future<ChefDto> getChef(String id) async {
    await mockDelay(450);
    final chef = _db.find(id);
    final taken = _db.consultations
        .where((c) => c.chefId == id && c.status != 'cancelled')
        .map((c) => c.scheduledAt)
        .toSet();
    final json = chef.toJson()
      ..['availableSlots'] = buildSlots(id)
          .where((s) => !taken.contains(s))
          .map((d) => d.toUtc().toIso8601String())
          .toList();
    return ChefDto.fromJson(json);
  }

  @override
  Future<ConsultationDto> requestConsultation(
      ConsultationRequestDto request) async {
    await mockDelay(900);
    if (request.note?.toLowerCase().contains('#fail') ?? false) {
      throw const ApiException(
          message: 'Hệ thống đặt lịch đang bận. Vui lòng thử lại.',
          statusCode: 503);
    }
    final chef = _db.find(request.chefId);
    final taken = _db.consultations.any(
      (c) =>
          c.chefId == request.chefId &&
          c.scheduledAt == request.scheduledAt &&
          c.status != 'cancelled',
    );
    if (taken) {
      throw const ApiException(
        message: 'Khung giờ này vừa có người đặt. Chọn giờ khác nhé.',
        statusCode: 409,
        code: 'slot_taken',
      );
    }
    final pkg = chef.packages.firstWhere((p) => p.id == request.packageId);
    final created = ConsultationDto(
      id: 'cs_${DateTime.now().millisecondsSinceEpoch}',
      chefId: chef.id,
      chefName: chef.fullName,
      packageName: pkg.name,
      priceVnd: pkg.priceVnd,
      durationMinutes: pkg.durationMinutes,
      mode: pkg.mode,
      scheduledAt: request.scheduledAt,
      status: 'pending',
      createdAt: DateTime.now(),
      note: request.note,
    );
    _db.consultations.insert(0, created);
    return created;
  }

  @override
  Future<List<ConsultationDto>> myConsultations() async {
    await mockDelay(500);
    return List.of(_db.consultations)
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }

  @override
  Future<ConsultationDto> cancelConsultation(String id) async {
    await mockDelay(500);
    final i = _db.consultations.indexWhere((c) => c.id == id);
    if (i < 0) {
      throw const ApiException(
          message: 'Không tìm thấy lịch hẹn.', statusCode: 404);
    }
    final updated = _db.consultations[i].copyWith(status: 'cancelled');
    _db.consultations[i] = updated;
    return updated;
  }
}

class _MockChefDb {
  _MockChefDb() {
    final now = DateTime.now();
    final upcoming = DateTime(now.year, now.month, now.day + 2, 19, 30);
    final past = DateTime(now.year, now.month, now.day - 10, 9);
    consultations.addAll([
      ConsultationDto(
        id: 'cs_seed_1',
        chefId: 'u_thu_ha',
        chefName: 'ThS. DD Phạm Thu Hà',
        packageName: 'Đánh giá dinh dưỡng & kế hoạch 4 tuần',
        priceVnd: 850000,
        durationMinutes: 75,
        mode: 'online',
        scheduledAt: upcoming,
        status: 'confirmed',
        createdAt: now.subtract(const Duration(days: 1)),
        note: 'Mình hay mệt buổi chiều, muốn kiểm tra B12 và sắt.',
      ),
      ConsultationDto(
        id: 'cs_seed_2',
        chefId: 'u_chef_tam',
        chefName: 'Lê Quang Tâm',
        packageName: 'Tư vấn thực đơn gia đình 7 ngày',
        priceVnd: 350000,
        durationMinutes: 60,
        mode: 'online',
        scheduledAt: past,
        status: 'completed',
        createdAt: past.subtract(const Duration(days: 3)),
      ),
    ]);
  }

  final List<ChefDto> chefs = seedChefs.map(ChefDto.fromJson).toList();
  final List<ConsultationDto> consultations = [];

  ChefDto find(String id) => chefs.firstWhere(
        (c) => c.id == id,
        orElse: () => throw const ApiException(
            message: 'Chuyên gia không còn hoạt động.', statusCode: 404),
      );
}

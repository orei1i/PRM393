// lib/features/chef_studio/data/mock_chef_studio_repository.dart
import '../../../core/session/user_role.dart';
import '../../../core/utils/mock_delay.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../domain/chef_studio_rules.dart';
import 'chef_studio_api_service.dart';
import 'models/chef_studio_models.dart';

/// Chef side of [MockCommerceDb]. "Me" is the chef profile whose `userId` is
/// the signed-in user. Errors: `#fail` in the bio or a doc title → 503;
/// invalid input → 400; not a chef → 403; no profile → 404.
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

  static void _check(String? error) {
    if (error != null) throw mockError(400, error, 'validation');
  }

  ChefProfileDto _profile(MockChefRow c) => ChefProfileDto.fromJson({
        'id': c.id,
        'userId': c.userId,
        'specialty': c.specialties.firstOrNull ?? '',
        'bio': c.bio,
        'pricePerDay': c.pricePerDay,
        'feedbackPricePerDay': c.feedbackPricePerDay,
        'minPlanDays': c.minPlanDays,
        'maxPlanDays': c.maxPlanDays,
        'acceptingBookings': c.acceptingBookings,
      });

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
    _check(ChefProfileRules.dayPrice(request.pricePerDay));
    _check(ChefProfileRules.dayPrice(request.feedbackPricePerDay));
    _check(ChefProfileRules.planDays(request.minPlanDays, request.maxPlanDays));
    final row = _db.chefOfUser(userId) ??
        MockChefRow.created(
          id: 'chef_$userId',
          userId: userId,
          fullName: currentUserName(),
          specialty: request.specialty,
          bio: request.bio.trim(),
        );
    if (!_db.chefs.contains(row)) _db.chefs.add(row);
    // SQL keeps a single `specialty`.
    row
      ..specialties = [request.specialty]
      ..bio = request.bio.trim()
      ..pricePerDay = request.pricePerDay
      ..feedbackPricePerDay = request.feedbackPricePerDay
      ..minPlanDays = request.minPlanDays
      ..maxPlanDays = request.maxPlanDays
      ..acceptingBookings = request.acceptingBookings;
    return _profile(row);
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

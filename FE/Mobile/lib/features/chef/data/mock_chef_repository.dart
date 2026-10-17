// lib/features/chef/data/mock_chef_repository.dart
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import 'chef_api_service.dart';
import 'models/chef_model.dart';

/// Reads chef profiles from the shared [MockCommerceDb], so a chef's new
/// prices or "Đang nhận yêu cầu" switch show up on the public profile right
/// away.
class MockChefRepository implements ChefApiService {
  MockCommerceDb get _db => MockCommerceDb.instance;

  @override
  Future<List<ChefDto>> listChefs({String? query, String? specialty}) async {
    await mockDelay(600);
    return _db.chefs
        .where((c) {
          final bySpecialty =
              specialty == null || c.specialties.contains(specialty);
          final byQuery = query == null ||
              query.trim().isEmpty ||
              matchesQuery(
                  '${c.fullName} ${c.headline} ${c.specialties.join(' ')} ${c.city}',
                  query);
          return bySpecialty && byQuery;
        })
        .map((c) => ChefDto.fromJson(_db.chefJson(c, detail: false)))
        .toList();
  }

  @override
  Future<ChefDto> getChef(String id) async {
    await mockDelay(450);
    return ChefDto.fromJson(_db.chefJson(_db.chef(id), detail: true));
  }
}

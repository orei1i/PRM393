// test/recipe_social/recipe_notes_repo_test.dart
// Private notes in mock mode (§3.4): only the author reads them, empty save
// deletes, 2000 characters at most, `#fail` → 503 with the old note kept;
// the controller (guests never request one).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_social_controllers.dart';

Matcher _apiError(int status, [String? message]) => throwsA(isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => message == null || e.message == message, 'message $message',
        isTrue));

MockRecipeCommunityRepository _as(String? userId) =>
    MockRecipeCommunityRepository(userId: userId);

void main() {
  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  test('a note is private to its author; empty save deletes it', () async {
    final minhAnh = _as('u_me');
    expect(await minhAnh.getMyNote('l5'), isNull, reason: 'none seeded');

    final saved =
        await minhAnh.saveMyNote('l5', '  Nêm mắm ruốc sau cùng cho thơm.  ');
    expect(saved?.entity.content, 'Nêm mắm ruốc sau cùng cho thơm.');
    expect(saved?.entity.recipeId, 'l5');
    expect((await minhAnh.getMyNote('l5'))?.entity.content,
        'Nêm mắm ruốc sau cùng cho thơm.');
    expect(await _as('u_chef_tam').getMyNote('l5'), isNull,
        reason: 'Tâm cannot read Minh Anh\'s note');
    expect(await minhAnh.getMyNote('menu_1'), isNull, reason: 'per recipe');

    expect(await minhAnh.saveMyNote('l5', '   '), isNull);
    expect(await minhAnh.getMyNote('l5'), isNull);

    await minhAnh.saveMyNote('l5', 'Lần sau thêm nấm.');
    await minhAnh.deleteMyNote('l5');
    expect(await minhAnh.getMyNote('l5'), isNull);
  });

  test('2000 characters at most; #fail → 503 keeps the old note', () async {
    final me = _as('u_me');
    await expectLater(me.saveMyNote('l5', 'a' * 2001),
        _apiError(400, 'Ghi chú tối đa 2000 ký tự'));
    expect((await me.saveMyNote('l5', 'a' * 2000))?.entity.content,
        hasLength(2000));
    await expectLater(me.saveMyNote('l5', 'Ghi chú #fail'), _apiError(503));
    expect((await me.getMyNote('l5'))?.entity.content, hasLength(2000));
  });

  test('guests → 401; unknown recipe → 404; private recipes take notes too',
      () async {
    await expectLater(_as(null).getMyNote('l5'), _apiError(401));
    await expectLater(_as(null).saveMyNote('l5', 'x'), _apiError(401));
    await expectLater(
        _as('u_me').saveMyNote('khong_co', 'Ghi chú'), _apiError(404));
    final variant = (await _as('u_me').createVariant(
            'l5',
            const CreateVariantRequestDto(
                name: 'Bún riêu nấm', swaps: {'rieu': 'rieu_nam'})))
        .toEntity();
    expect(
        (await _as('u_me').saveMyNote(variant.id, 'Nấu cho mẹ'))
            ?.entity
            .content,
        'Nấu cho mẹ');
  });

  test('the controller: none for guests, save / delete update the state',
      () async {
    final guest = ProviderContainer(
        overrides: [plannerUserIdProvider.overrideWithValue(null)]);
    addTearDown(guest.dispose);
    guest.listen(recipeNoteProvider('l5'), (_, __) {});
    expect(await guest.read(recipeNoteProvider('l5').future), isNull);

    final container = ProviderContainer(
        overrides: [plannerUserIdProvider.overrideWithValue('u_me')]);
    addTearDown(container.dispose);
    final provider = recipeNoteProvider('l5');
    container.listen(provider, (_, __) {});
    expect(await container.read(provider.future), isNull);

    final controller = container.read(provider.notifier);
    await controller.save('Nêm mắm ruốc sau cùng.');
    expect(container.read(provider).requireValue?.content,
        'Nêm mắm ruốc sau cùng.');
    await expectLater(controller.save('#fail'), _apiError(503));
    expect(container.read(provider).requireValue?.content,
        'Nêm mắm ruốc sau cùng.',
        reason: 'unchanged on error');
    expect(await controller.save(''), isNull);
    expect(container.read(provider).requireValue, isNull);
    await controller.save('Lần sau thêm nấm.');
    await controller.delete();
    expect(container.read(provider).requireValue, isNull);
  });
}

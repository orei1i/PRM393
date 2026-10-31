// integration_test_be/be_bug_pins_test.dart
//
// Today's bad behaviour of the BE, one test per bug of the report list (README,
// "Lỗi BE đã biết"). A failure here is good news: the bug looks fixed, and the
// message says which workaround to remove. Run them alone with
// `--tags be-bug-pin`.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';

import 'be_harness.dart';

/// [revert] is what to do once the BE no longer behaves this way.
void pinBug(String id, String behaviour, Future<void> Function() body,
    {required String revert}) {
  test(
    '$id: $behaviour',
    () async {
      try {
        await body();
      } on TestFailure catch (e) {
        fail('$id no longer reproduces, so the BE changed: $revert\n'
            '${e.message}');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: beBugPinTag,
  );
}

Map<String, Object?> profileBody({
  String goal = 'maintain',
  double weightKg = 66,
  List<String> mealPattern = const ['breakfast', 'lunch', 'dinner'],
  List<Map<String, Object?>> allergies = const [],
}) =>
    {
      'heightCm': 170,
      'weightKg': weightKg,
      'goal': goal,
      'gender': 'Female',
      'birthYear': 1997,
      'activityLevel': 'light',
      'mealPattern': mealPattern,
      'allergies': allergies,
      'dietaryRestrictions': <String>[],
    };

String get _thisMonday => toApiDate(startOfWeek(DateTime.now()));

String get _today => toApiDate(DateTime.now());

const _noPlanId = '000000000000000000000000';

Future<void> main() async {
  final be = await BeHarness.start();

  group('BE bug pins', skip: be.skipReason, () {
    late BeUser me;

    /// A post that is deleted with the test.
    Future<String> newPost(BeUser author,
        {String mediaType = 'Text', String? mediaUrl}) async {
      final res = await author.raw('POST', '/posts', data: {
        'type': 'discussion',
        'title': 'Bài ghim lỗi BE',
        'body': 'Bài dùng để ghim một lỗi đã biết của BE.',
        'tags': <String>[],
        'mediaType': mediaType,
        'mediaUrl': mediaUrl,
      });
      final id = res.dataMap['id'] as String;
      addTearDown(() => author.raw('DELETE', '/posts/$id'));
      return id;
    }

    /// A new account with a profile and a generated week.
    Future<(BeUser, Map<String, dynamic>)> withPlan() async {
      final user = await be.newUser(name: 'FE IT Pin Plan');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final plan = await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      return (user, plan.dataMap);
    }

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Pin');
    });

    pinBug('B1', 'POST /api/v1/vision/scan is 500 (two routes match)',
        () async {
      final res = await me.raw('POST', '/vision/scan',
          data: oneFile('image', 'a.png', pngBytes()));
      expect(res.status, 500);
      final root = await me.raw('POST', '${Env.apiOrigin}/vision/scan',
          data: oneFile('image', 'a.png', pngBytes()));
      expect(root.status, 200);
    }, revert: 'make ApiEndpoints.visionScan the relative /vision/scan again.');

    pinBug('B2', 'there is no admin login route', () async {
      final res = await rawRequest('POST', '/auth/admin/login',
          data: {'email': randomEmail(), 'password': randomPassword()});
      expect(res.status, anyOf(404, 405));
    }, revert: 'point the FE/Web admin login at /auth/admin/login.');

    pinBug('B3', 'GET and PUT /users/{id} are 403 for the member themselves',
        () async {
      expect((await me.raw('GET', '/users/${me.id}')).status, 403);
      final put = await me.raw('PUT', '/users/${me.id}',
          data: {'fullName': 'Tên mới', 'phone': null});
      expect(put.status, 403);
    },
        revert: 'drop profileUpdateForbiddenMessage in '
            'profile_api_service.dart, and check the BE has an ownership check '
            '(id == sub or Admin).');

    pinBug('B4', 'other members can read a private recipe', () async {
      final name = 'Món riêng FEIT ${randomHex(8)}';
      final created = await me.raw('POST', '/recipes', data: {
        'name': name,
        'calories': 500,
        'ingredients': ['Đậu hũ'],
        'instructions': ['Nấu'],
      });
      expect(created.status, anyOf(200, 201));
      final other = await be.newUser(name: 'FE IT Pin 2');
      final res = await other.raw(
          'GET', '/meal-plans/$_noPlanId/swap-suggestions',
          query: {'date': _today, 'slot': 'snack_am', 'limit': 500});
      expect(res.dataList.map((r) => r['name']), contains(name));
    }, revert: 'nothing in the FE; take B4 off the README list.');

    test(
      'B5: the seed accounts of the API doc do not exist',
      () {},
      skip: 'Not pinned: it needs the credentials of TAI_LIEU_API_CHO_FRONTEND '
          'and depends on how the test DB was seeded. Device QA registers its '
          'own account.',
      tags: beBugPinTag,
    );

    pinBug('B6', 'PATCH meals ignores source and portion', () async {
      final (user, plan) = await withPlan();
      final planId = plan['id'] as String;
      final suggestions = await user.raw(
          'GET', '/meal-plans/$planId/swap-suggestions',
          query: {'date': _today, 'slot': 'lunch', 'limit': 3});
      final recipeId = suggestions.dataList.first['id'];
      final res = await user.raw('PATCH', '/meal-plans/$planId/meals', data: {
        'date': _today,
        'slot': 'lunch',
        'recipeId': recipeId,
        'source': 'recipe',
        'portion': 2,
      });
      expect(res.status, 200);
      final meal = (res.dataMap['meals'] as Map<String, dynamic>)['lunch']
          as Map<String, dynamic>;
      expect(meal['source'], 'manual');
      expect(meal['portion'], anyOf(isNull, 1, 1.0));
    }, revert: 'drop the manual → recipe mapping in RecipeDto.fromJson.');

    pinBug('B7', 'POST meals/batch drops macros, sourceName and recipeId',
        () async {
      final (user, _) = await withPlan();
      final res =
          await user.raw('POST', '/meal-plans/current/meals/batch', data: {
        'meals': [
          {
            'date': _today,
            'slot': 'snack_pm',
            'name': 'Sinh tố',
            'calories': 150,
            'proteinG': 10,
            'source': 'chef',
            'sourceName': 'Bếp X',
            'recipeId': _noPlanId,
          },
        ],
      });
      expect(res.status, anyOf(200, 201));
      final day =
          (res.dataMap['days'] as List<Object?>).first! as Map<String, dynamic>;
      final meal = (day['meals'] as Map<String, dynamic>)['snack_pm']
          as Map<String, dynamic>;
      expect(meal['proteinG'], isNull);
      expect(meal['sourceName'], isNull);
      expect(meal['recipeId'], isNull);
    },
        revert: 'send macros on AddMealRequestDto, turn on '
            'BackendModules.manualMealMacros, and show the chef name again.');

    pinBug('B8', 'a new goal does not re-aim the current plan', () async {
      final (user, plan) = await withPlan();
      final targets = plan['dailyTargets'] as Map<String, dynamic>;
      final saved = await user.raw('PUT', '/health-profile/me',
          data: profileBody(goal: 'lose'));
      expect(saved.dataMap['targetCalories'], isNot(targets['calories']));
      final after = await user.raw('GET', '/meal-plans/current');
      expect(
        (after.dataMap['dailyTargets'] as Map<String, dynamic>)['calories'],
        targets['calories'],
      );
    }, revert: 'drop the _aimed overlay in MealPlanController.');

    pinBug('B9', 'a PUT resets what it does not get; null is a 400', () async {
      final user = await be.newUser(name: 'FE IT Pin B9');
      final res = await user.raw('PUT', '/health-profile/me', data: {
        'heightCm': 170,
        'weightKg': 66,
        'goal': 'maintain',
        'allergies': <Object?>[],
        'dietaryRestrictions': <String>[],
      });
      expect(res.status, 200);
      expect(res.dataMap['gender'], 'Other');
      expect(res.dataMap['birthYear'], 1998);
      final bad = await user.raw('PUT', '/health-profile/me',
          data: {...profileBody(), 'birthYear': null});
      expect(bad.status, 400);
    },
        revert: 'UpdateHealthProfileRequestDto.toBackendJson no longer needs '
            '`saved`, nor the extra GET in updateHealthProfile.');

    pinBug('B10', 'goal lose_weight silently means 0 %', () async {
      final user = await be.newUser(name: 'FE IT Pin B10');
      final keep = await user.raw('PUT', '/health-profile/me',
          data: profileBody(goal: 'maintain'));
      final wrong = await user.raw('PUT', '/health-profile/me',
          data: profileBody(goal: 'lose_weight'));
      expect(wrong.status, 200);
      expect(wrong.dataMap['targetCalories'], keep.dataMap['targetCalories']);
    }, revert: 'toBackendJson can send HealthGoal.apiValue as it is.');

    pinBug('B11', 'generate ignores the meal pattern', () async {
      final user = await be.newUser(name: 'FE IT Pin B11');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(mealPattern: ['lunch', 'dinner']));
      final plan = await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final day = (plan.dataMap['days'] as List<Object?>).first!
          as Map<String, dynamic>;
      expect(
          (day['meals'] as Map<String, dynamic>).keys, contains('breakfast'));
    },
        revert: 'nothing in the FE; check the planner labels of the extra '
            'slots.');

    pinBug('B12', 'dev uploads return a host-relative url', () async {
      final res = await me.raw('POST', '/media/images',
          data: oneFile('file', 'a.png', pngBytes()));
      expect(res.status, anyOf(200, 201));
      expect(res.dataMap['mediaUrl'], startsWith('/'));
    }, revert: 'absoluteMediaUrl is no longer needed for uploads.');

    pinBug('B13', 'the fridge stores non-vegan food as vegan', () async {
      final user = await be.newUser(name: 'FE IT Pin B13');
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Trứng gà'},
        ],
      });
      final list = await user.raw('GET', '/users/me/ingredients');
      final row =
          list.dataList.singleWhere((r) => r['ingredient'] == 'Trứng gà');
      expect(row['isVegan'], isTrue);
    }, revert: '_refuseNonVegan in pantry_api_service.dart may go.');

    pinBug('B14', 'allergyWarning never fires for a standard allergen',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B14');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'allergenId': 'peanut', 'name': 'Đậu phộng'},
          ]));
      final res = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Đậu phộng'},
        ],
      });
      final row =
          res.dataList.singleWhere((r) => r['ingredient'] == 'Đậu phộng');
      expect(row['allergyWarning'], isNull);
    }, revert: 'nothing in the FE; check how the row shows the warning.');

    pinBug('B15', 'the feed returns nextCursor but ignores cursor and limit',
        () async {
      await newPost(me);
      final first = await me.raw('GET', '/posts', query: {'limit': 3});
      expect(first.dataMap['pageSize'], 10);
      final cursor = first.dataMap['nextCursor'];
      final again = await me.raw('GET', '/posts', query: {'cursor': cursor});
      expect(again.dataMap['page'], 1);
    }, revert: 'nextFeedCursor in backend_posts.dart can read nextCursor.');

    pinBug('B16', 'replies past 2 are unreachable; a deleted root orphans them',
        () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      final rootId = root.dataMap['id'];
      for (var i = 0; i < 3; i++) {
        await me.raw('POST', '/posts/$id/comments',
            data: {'content': 'Phản hồi $i', 'parentId': rootId});
      }
      final list = await me.raw('GET', '/posts/$id/comments');
      final first = list.dataList.single;
      expect(first['replyCount'], 3);
      expect(first['replies'], hasLength(2));
      final route = await me.raw('GET', '/posts/$id/comments/$rootId/replies');
      expect(route.status, anyOf(404, 405));

      await me.raw('DELETE', '/comments/$rootId');
      final post = await me.raw('GET', '/posts/$id');
      expect(post.dataMap['commentCount'], 3);
    },
        revert: 'turn on BackendModules.commentReplyPaging and drop the '
            'static "more replies" label.');

    pinBug('B17', 'a comment has updatedAt although it was never edited',
        () async {
      final id = await newPost(me);
      await me.raw('POST', '/posts/$id/comments', data: {'content': 'Một'});
      final list = await me.raw('GET', '/posts/$id/comments');
      expect(list.dataList.single['updatedAt'], isNotNull);
    },
        revert: 'drop `updatedAt: null` in '
            'RemoteCommunityApiService._commentJson.');

    pinBug('B18', 'no refresh token and no refresh route', () async {
      final res = await rawRequest('POST', '/auth/login',
          data: {'email': me.email, 'password': me.password});
      expect(res.dataMap['refreshToken'], isNull);
      final refresh = await rawRequest('POST', '/auth/refresh',
          data: {'refreshToken': 'x'});
      expect(refresh.status, anyOf(404, 405));
    },
        revert: 'add the refresh flow; UnauthorizedInterceptor would try it '
            'first.');

    pinBug('B19', 'POST /recipes ignores prepMinutes and turns 0 kcal into 300',
        () async {
      final res = await me.raw('POST', '/recipes', data: {
        'name': 'Món ghim B19',
        'calories': 0,
        'prepMinutes': 20,
        'ingredients': ['Đậu hũ'],
        'instructions': ['Nấu'],
      });
      expect(res.dataMap['prepMinutes'], 15);
      expect(res.dataMap['calories'], 300);
    }, revert: 'nothing in the FE; take B19 off the README list.');

    pinBug('B20', '/catalog/allergens ignores q', () async {
      final all = await rawRequest('GET', '/catalog/allergens');
      final some = await rawRequest('GET', '/catalog/allergens',
          query: {'q': 'khong co chat nay'});
      expect(some.dataList.length, all.dataList.length);
    }, revert: 'RemoteAllergenApiService may search on the server.');

    pinBug('B21', 'a video post claims an AI status with no API behind it',
        () async {
      final upload = await me.raw('POST', '/media/videos',
          data: oneFile('file', 'a.mp4', mp4Bytes()));
      final id = await newPost(me,
          mediaType: 'Video', mediaUrl: upload.dataMap['mediaUrl'] as String?);
      final post = await me.raw('GET', '/posts/$id');
      final video = post.dataMap['video'] as Map<String, dynamic>;
      expect(video['aiStatus'], 'ready');
      expect(video['id'], id);
      expect(video['durationSeconds'], 0);
    }, revert: 'drop `adapted.remove("video")` in adaptBackendPost.');

    pinBug('B22', '/users/me stats stay 0', () async {
      await newPost(me);
      final res = await me.raw('GET', '/users/me');
      final stats = res.dataMap['stats'] as Map<String, dynamic>;
      expect(stats['posts'], 0);
    }, revert: 'profileStatsProvider can trust the BE numbers.');

    pinBug('B23', 'a wrong reset code is a raw invalid_code, with no code',
        () async {
      await rawRequest('POST', '/auth/forgot-password',
          data: {'email': me.email});
      final res = await rawRequest('POST', '/auth/verify-reset-code',
          data: {'email': me.email, 'code': '000000'});
      expect(res.status, 400);
      expect(res.json['message'], 'invalid_code');
      expect(res.json['code'], isNull);
    }, revert: 'AuthErrors.localize no longer needs the code in `message`.');

    pinBug('B24', '/meal-plans/current falls back to an old plan', () async {
      final user = await be.newUser(name: 'FE IT Pin B24');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final oldMonday =
          startOfWeek(DateTime.now().subtract(const Duration(days: 28)));
      await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': toApiDate(oldMonday)});
      final current = await user.raw('GET', '/meal-plans/current');
      expect(current.status, 200);
      expect(current.dataMap['startDate'], startsWith(toApiDate(oldMonday)));
    },
        revert: 'drop the isSameDay week check in '
            'RemoteMealPlannerApiService.getCurrentMealPlan.');

    pinBug('B25', 'validation errors are ProblemDetails, not the envelope',
        () async {
      final res = await rawRequest('POST', '/auth/register', data: {
        'fullName': 'FE IT',
        'email': 'not-an-email',
        'password': randomPassword(),
      });
      expect(res.status, 400);
      expect(res.json['errors'], isNotNull);
      expect(res.json.containsKey('success'), isFalse);
    }, revert: 'the ProblemDetails branch of mapDioException may go.');

    pinBug(
        'B26',
        'swap-suggestions does not check the plan id, and an unmatched slot '
            'returns every recipe', () async {
      final res = await me.raw('GET', '/meal-plans/$_noPlanId/swap-suggestions',
          query: {'date': _today, 'slot': 'snack_am', 'limit': 200});
      expect(res.status, 200);
      expect(res.dataList.length, greaterThanOrEqualTo(29));
    },
        revert: 'RecipeCatalog relies on this: pass a real plan id, or read '
            'the tagged slots (already its fallback), or GET /recipes/{id}.');

    pinBug('B27', 'three reports hide a post, with no admin route to restore',
        () async {
      final id = await newPost(me);
      for (var i = 0; i < 3; i++) {
        final reporter = await be.newUser(name: 'FE IT Pin B27');
        await reporter
            .raw('POST', '/posts/$id/reports', data: {'reason': 'spam'});
      }
      final read = await rawRequest('GET', '/posts/$id');
      expect(read.status, 404);
    },
        revert: 'nothing in the FE; the web moderation queue can use the '
            'route.');

    pinBug('B28', 'liking again after an unlike is 500 (E11000 on PostLikes)',
        () async {
      final id = await newPost(me);
      expect(
          (await me.raw('POST', '/posts/$id/like')).dataMap['liked'], isTrue);
      expect(
          (await me.raw('POST', '/posts/$id/like')).dataMap['liked'], isFalse);
      expect((await me.raw('POST', '/posts/$id/like')).status, 500);
    },
        revert: 'nothing to revert in the FE (setLiked just works again); take '
            'B28 off the README list.');

    pinBug('B29', 'POST /meal-plans returns a filled week as it is', () async {
      final (user, plan) = await withPlan();
      final res = await user.raw('POST', '/meal-plans',
          data: {'startDate': _thisMonday, 'empty': true});
      expect(res.status, 200);
      expect(res.dataMap['id'], plan['id']);
      final days =
          (res.dataMap['days'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(days.any((d) => (d['meals'] as Map).isNotEmpty), isTrue);
    },
        revert: 'BackendModules.planClear: show "Tự lên thực đơn" on a filled '
            'week again.');

    pinBug('B30', 'swap-suggestions offers the dish already in the slot',
        () async {
      final (user, plan) = await withPlan();
      final today = (plan['days'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['date'] == _today);
      final current = (today['meals'] as Map)['lunch'] as Map;
      final res = await user.raw(
          'GET', '/meal-plans/${plan['id']}/swap-suggestions',
          query: {'date': _today, 'slot': 'lunch', 'limit': 4});
      expect(res.dataList.map((r) => r['id']), contains(current['recipeId']));
    },
        revert: 'getSwapSuggestions: back to limit 3 (swapChoices still leaves '
            'the current dish out).');
  });
}

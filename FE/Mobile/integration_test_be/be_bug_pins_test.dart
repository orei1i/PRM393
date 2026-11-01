// integration_test_be/be_bug_pins_test.dart
//
// What is still wrong on the BE, one test per open bug of the report list
// (README, "Lỗi BE đã biết"), new ones included. A failure here is good news:
// the bug looks fixed, and the message says what to do in the app. What the BE
// fixed is checked as ordinary behaviour in the other files. Run them alone with
// `--tags be-bug-pin`.
import 'package:flutter_test/flutter_test.dart';
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
  double heightCm = 170,
  double weightKg = 66,
  String activity = 'light',
  List<Map<String, Object?>> allergies = const [],
}) =>
    {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'goal': goal,
      'gender': 'Female',
      'birthYear': 1997,
      'activityLevel': activity,
      'mealPattern': ['breakfast', 'lunch', 'dinner'],
      'allergies': allergies,
      'dietaryRestrictions': <String>[],
    };

String get _thisMonday => toApiDate(startOfWeek(DateTime.now()));

String get _today => toApiDate(DateTime.now());

Future<void> main() async {
  final be = await BeHarness.start();

  group('BE bug pins', skip: be.skipReason, () {
    late BeUser me;

    /// A post that is deleted with the test.
    Future<String> newPost(BeUser author) async {
      final res = await author.raw('POST', '/posts', data: {
        'type': 'discussion',
        'title': 'Bài ghim lỗi BE',
        'body': 'Bài dùng để ghim một lỗi đã biết của BE.',
        'tags': <String>[],
        'mediaType': 'Text',
        'mediaUrl': null,
      });
      final id = res.dataMap['id'] as String;
      addTearDown(() => author.raw('DELETE', '/posts/$id'));
      return id;
    }

    /// `isVegan` of a name just added to a new fridge.
    Future<bool?> veganOnBe(String name) async {
      final user = await be.newUser(name: 'FE IT Pin Vegan');
      final res = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': name},
        ],
      });
      return res.dataList.single['isVegan'] as bool?;
    }

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Pin');
    });

    test(
      'B42: a password reset leaves the old refresh token alive',
      () {},
      skip: 'Not pinned: the reset code is only in the BE stdout. Seen by hand '
          'on 2026-11-01: refresh with the old token after a reset is 200.',
      tags: beBugPinTag,
    );

    test(
      'B43: a profile saved with goal "lose" reads as "maintain"',
      () {},
      skip: 'Not pinned: the API no longer takes that value, it takes editing '
          'the DB. Seen by hand on 2026-11-01: goal maintain, target of -15 %.',
      tags: beBugPinTag,
    );

    pinBug('B9', 'a PUT without activityLevel still resets it to light',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B9');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(activity: 'active'));
      final res = await user.raw('PUT', '/health-profile/me', data: {
        'heightCm': 170,
        'weightKg': 66,
        'goal': 'maintain',
        'allergies': <Object?>[],
        'dietaryRestrictions': <String>[],
      });
      expect(res.dataMap['activityLevel'], 'light');
    },
        revert: 'UpdateHealthProfileRequestDto.toBackendJson no longer needs '
            '`saved`, nor the extra GET in updateHealthProfile.');

    pinBug(
        'B13',
        'the fridge check goes by words: fish with tomato is vegan, spinach '
            'is not', () async {
      expect(await veganOnBe('Cá sốt cà chua'), isTrue);
      expect(await veganOnBe('Dầu hào'), isTrue);
      expect(await veganOnBe('Rau chân vịt'), isFalse);
      expect(await veganOnBe('Đậu gà'), isFalse);
      expect(await veganOnBe('Bơ'), isFalse,
          reason: 'its own catalogue lists Bơ as vegan, and it seeds avocado '
              'recipes');
    },
        revert: 'VeganVerdict.server can state it as a fact; check that '
            '_refuseNonVegan still adds anything.');

    pinBug('B14', 'tamarind ("Me") warns about a sesame allergy', () async {
      final user = await be.newUser(name: 'FE IT Pin B14');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'allergenId': 'sesame', 'name': 'Mè'},
          ]));
      final res = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Me'},
        ],
      });
      expect(res.dataList.single['allergyWarning'], isNotNull);
    }, revert: 'nothing in the FE; take this part of B14 off the README.');

    pinBug('B17', 'a reply that got a reply has an updatedAt', () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      final reply = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': root.dataMap['id']});
      await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Hai', 'parentId': reply.dataMap['id']});
      final list = await me.raw(
          'GET', '/posts/$id/comments/${root.dataMap['id']}/replies');
      expect(list.dataList.single['updatedAt'], isNotNull);
    },
        revert: 'drop `updatedAt: null` in '
            'RemoteCommunityApiService._commentJson.');

    pinBug('B23', 'the reset route answers with a raw invalid_code', () async {
      final res = await rawRequest('POST', '/auth/reset-password',
          data: {'resetToken': 'khong-co', 'newPassword': randomPassword()});
      expect(res.status, 400);
      expect(res.json['message'], 'invalid_code');
      expect(res.json['code'], isNull);
    }, revert: 'AuthErrors.localize no longer needs the code in `message`.');

    pinBug('B31', 'a large target is out of reach: a portion stops at 1.5',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B31');
      final profile = await user.raw('PUT', '/health-profile/me',
          data: profileBody(
              goal: 'gain_weight',
              heightCm: 190,
              weightKg: 110,
              activity: 'active'));
      final target = profile.dataMap['targetCalories'] as num;
      final plan = await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final days =
          (plan.dataMap['days'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final day in days) {
        expect(day['totalCalories'] as num, lessThan(target * 0.8));
        for (final meal in (day['meals'] as Map).values) {
          expect((meal as Map)['portion'] as num, lessThanOrEqualTo(1.5));
        }
      }
    }, revert: 'nothing in the FE; take B31 off the README list.');

    pinBug('B33', 'a dish with no prepMinutes is given 15', () async {
      final user = await be.newUser(name: 'FE IT Pin B33');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final res = await user.raw('POST', '/meal-plans/current/meals', data: {
        'date': _today,
        'slot': 'snack_pm',
        'name': 'Sinh tố',
        'calories': 150,
      });
      final meal = (res.dataMap['meals'] as Map<String, dynamic>)['snack_pm']
          as Map<String, dynamic>;
      expect(meal['prepMinutes'], 15);
    }, revert: 'nothing in the FE; take B33 off the README list.');

    pinBug('B35', 'the auth errors and a few others are garbled', () async {
      final wrong = await rawRequest('POST', '/auth/login',
          data: {'email': me.email, 'password': randomPassword()});
      expect(wrong.status, 401);
      expect(wrong.json['message'], contains('khÃ'));
      final taken = await rawRequest('POST', '/auth/register', data: {
        'fullName': 'FE IT',
        'email': me.email,
        'password': randomPassword(),
      });
      expect(taken.status, 409);
      expect(taken.json['message'], contains('Ä'));
    },
        revert:
            'drop `_garbled` in api_exception.dart; AuthErrors.localize may '
            'keep mapping by status.');

    pinBug('B36', 'POST metrics takes anything and overwrites the profile',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B36');
      final noProfile = await user
          .raw('POST', '/health-profile/me/metrics', data: {'weightKg': 70});
      expect(noProfile.status, 201);
      expect(noProfile.dataMap['heightCm'], 170,
          reason: 'a height nobody gave');

      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final bad = await user
          .raw('POST', '/health-profile/me/metrics', data: {'weightKg': -5});
      expect(bad.status, 201);
      final profile = await user.raw('GET', '/health-profile/me');
      expect(profile.dataMap['weightKg'], -5);
      expect(profile.dataMap['bmi'], 0);
      final empty =
          await user.raw('POST', '/health-profile/me/metrics', data: {});
      expect(empty.status, 201, reason: 'an empty body writes a row');
    },
        revert: 'BodyProgress.validateMeasurement in logBodyMeasurement may '
            'go; the sheet keeps its own rules.');

    pinBug(
        'B37',
        'POST metrics leaves the target and the week as they were, and drops '
            '`source`', () async {
      final user = await be.newUser(name: 'FE IT Pin B37');
      final saved =
          await user.raw('PUT', '/health-profile/me', data: profileBody());
      final target = saved.dataMap['targetCalories'];
      await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final logged = await user.raw('POST', '/health-profile/me/metrics',
          data: {'weightKg': 90, 'source': 'check_in'});
      expect(logged.dataMap.containsKey('source'), isFalse);
      final profile = await user.raw('GET', '/health-profile/me');
      expect(profile.dataMap['weightKg'], 90);
      expect(profile.dataMap['targetCalories'], target);
      final plan = await user.raw('GET', '/meal-plans/current');
      expect((plan.dataMap['dailyTargets'] as Map)['calories'], target);
    },
        revert: 'drop the PUT in RemoteMealPlannerApiService.'
            'logBodyMeasurement; a row with `source` can read "Từ Hồ sơ sức '
            'khoẻ" on the real BE again.');

    pinBug('B38', 'a second add without a quantity resets the row to 1',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B38');
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Cà chua', 'quantity': 300, 'unit': 'g'},
        ],
      });
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Cà chua'},
        ],
      });
      final list = await user.raw('GET', '/users/me/ingredients');
      expect(list.dataList.single['quantity'], 1);
      expect(list.dataList.single['unit'], 'g');
    },
        revert: 'RemotePantryApiService._keepingAmounts may go, with its extra '
            'GET.');

    pinBug(
        'B39',
        'a reply to a reply is stored there: no route lists it, deleting the '
            'root leaves it counted', () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      final rootId = root.dataMap['id'];
      final reply = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': rootId});
      final nested = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Hai', 'parentId': reply.dataMap['id']});
      expect(nested.dataMap['parentId'], reply.dataMap['id']);
      final replies =
          await me.raw('GET', '/posts/$id/comments/$rootId/replies');
      expect(replies.dataList, hasLength(1));

      await me.raw('DELETE', '/comments/$rootId');
      final post = await me.raw('GET', '/posts/$id');
      expect(post.dataMap['commentCount'], 1);
      final list = await me.raw('GET', '/posts/$id/comments');
      expect(list.dataList, isEmpty);
    },
        revert: 'nothing in the FE (it always answers the top-level comment); '
            'take B39 off the README list.');

    pinBug('B40', 'the replies route takes any post id', () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': root.dataMap['id']});
      final other = await newPost(me);
      final res = await me.raw(
          'GET', '/posts/$other/comments/${root.dataMap['id']}/replies');
      expect(res.status, 200);
      expect(res.dataList, hasLength(1));
    }, revert: 'nothing in the FE; take B40 off the README list.');

    pinBug(
        'B41', 'writes are not checked: a beef recipe, a slot that is not one',
        () async {
      final recipe = await me.raw('POST', '/recipes', data: {
        'name': 'Thịt bò xào',
        'calories': -100,
        'prepMinutes': -5,
        'ingredients': ['Thịt bò'],
        'instructions': ['Nấu'],
      });
      expect(recipe.status, 201);
      expect(recipe.dataMap['calories'], -100);

      final user = await be.newUser(name: 'FE IT Pin B41');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final plan = await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final dish = await user.raw('POST', '/meal-plans/current/meals', data: {
        'date': _today,
        'slot': 'khong-co-bua-nay',
        'name': 'Thịt bò',
        'calories': 100,
      });
      expect(dish.status, 200);
      final suggestion = await user.raw(
          'GET', '/meal-plans/${plan.dataMap['id']}/swap-suggestions',
          query: {'date': _today, 'slot': 'lunch', 'limit': 1});
      final patched = await user
          .raw('PATCH', '/meal-plans/${plan.dataMap['id']}/meals', data: {
        'date': _today,
        'slot': 'lunch',
        'recipeId': suggestion.dataList.single['id'],
        'source': 'khong-co-nguon-nay',
      });
      final lunch = (patched.dataMap['meals'] as Map)['lunch'] as Map;
      expect(lunch['source'], 'khong-co-nguon-nay');
    }, revert: 'nothing in the FE: the app checks these before sending.');
  });
}

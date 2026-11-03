// integration_test_be/be_bug_pins_test.dart
//
// guardFixed: what the BE fixed and the app now relies on, its workaround being
// gone. A failure here is a regression on the BE, and the message says what
// breaks in the app. A bug that comes back or a new one gets a `pinBug` again:
// a test of what is wrong, whose failure says what to do in the app once fixed.
// Run them alone with `--tags be-bug-pin`.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';

import 'be_harness.dart';

/// [relies] is what the app does without a workaround because of this.
void guardFixed(String id, String behaviour, Future<void> Function() body,
    {required String relies}) {
  test(
    '$id fixed: $behaviour',
    () async {
      try {
        await body();
      } on TestFailure catch (e) {
        fail('$id is back on the BE, and the app relies on it: $relies\n'
            '${e.message}');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: beBugPinTag,
  );
}

/// What a source file saved in the wrong encoding looks like (B35); the same
/// check as `_garbled` in api_exception.dart.
final _garbled = RegExp(r'Ã[\u0080-\u00BF\u2018-\u203A]|Ä|Æ|á[º»]|â€');

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
      'B43 fixed: an old goal "lose" is migrated at startup',
      () {},
      skip: 'Not pinned: an old row takes editing the DB. The BE has its own '
          'test, B43_Old_goals_are_migrated_and_read_right_even_before_that.',
      tags: beBugPinTag,
    );

    // ---------------------------------------------------------------- fixed --

    guardFixed('B9', 'a PUT without activityLevel keeps it, and the target',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B9');
      final first = await user.raw('PUT', '/health-profile/me',
          data: profileBody(activity: 'active'));
      final res = await user.raw('PUT', '/health-profile/me', data: {
        'heightCm': 170,
        'weightKg': 66,
        'goal': 'maintain',
        'allergies': <Object?>[],
        'dietaryRestrictions': <String>[],
      });
      expect(res.dataMap['activityLevel'], 'active');
      expect(res.dataMap['targetCalories'], first.dataMap['targetCalories']);
    },
        relies: 'UpdateHealthProfileRequestDto leaves a missing activity level '
            'out, with no GET before the PUT.');

    guardFixed(
        'B13',
        'the fridge check no longer goes by words: sườn non, gelatin, dê, whey, '
            'hải sản, tiết canh are not vegan; sữa chua dừa, phô mai hạt điều, '
            'spinach and avocado are', () async {
      for (final name in [
        'Cá sốt cà chua',
        'Trứng chiên cà chua',
        'Dầu hào',
        'Sườn non',
        'Gelatin',
        'Dê',
        'Whey',
        'Hải sản',
        'Tiết canh',
      ]) {
        expect(await veganOnBe(name), isFalse, reason: name);
      }
      for (final name in [
        'Rau chân vịt',
        'Đậu gà',
        'Bơ',
        'Quả bơ',
        'Sữa chua dừa',
        'Phô mai hạt điều',
      ]) {
        expect(await veganOnBe(name), isTrue, reason: name);
      }
    },
        relies: 'RemotePantryApiService takes back out what the BE calls '
            'non-vegan, so a vegan food would leave the fridge again, and '
            'the fridge shows what the BE lets through as vegan.');

    guardFixed(
        'B69',
        'a post off the feed takes no likes or comments from others, and lists '
            'no comments to a guest; its author and an admin still can',
        () async {
      final author = await be.newUser(name: 'FE IT Pin B69');
      final other = await be.newUser(name: 'FE IT Pin B69 Other');
      final id = await newPost(author);
      await author.raw('POST', '/posts/$id/comments',
          data: {'content': 'Trước khi ẩn'});
      final admin = await be.adminToken();
      final hidden = await rawRequest('POST', '/admin/posts/$id/actions',
          token: admin, data: {'action': 'hide'});
      expect(hidden.dataMap['status'], 'Hidden');

      expect((await other.raw('GET', '/posts/$id')).status, 404);
      expect((await other.raw('POST', '/posts/$id/like')).status, 404);
      expect(
          (await other.raw('POST', '/posts/$id/comments',
                  data: {'content': 'Sau khi ẩn'}))
              .status,
          404);
      expect((await rawRequest('GET', '/posts/$id/comments')).status, 404);
      expect((await other.raw('GET', '/posts/$id/comments')).status, 404);
      expect((await author.raw('GET', '/posts/$id')).status, 200);
      expect((await author.raw('GET', '/posts/$id/comments')).status, 200);
    },
        relies: 'PostDetailScreen reads a 404 on a like or a comment as "the '
            'post is gone" and takes it off the feed.');

    guardFixed(
        'B70',
        'names that differ only by accent are two rows when short: "Mè" after '
            '"Me" warns about sesame; long names still merge', () async {
      final user = await be.newUser(name: 'FE IT Pin B70');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'allergenId': 'sesame', 'name': 'Mè'},
          ]));
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Me'},
        ],
      });
      final res = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Mè'},
        ],
      });
      expect(res.dataList.single['ingredient'], 'Mè');
      expect(res.dataList.single['allergyWarning'], 'Cảnh báo dị ứng: Mè');
      final list = await user.raw('GET', '/users/me/ingredients');
      expect(list.dataList, hasLength(2));
      final merged = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Đậu hũ'},
          {'ingredient': 'dau hu'},
        ],
      });
      expect(merged.status, 200);
      final after = await user.raw('GET', '/users/me/ingredients');
      expect(after.dataList, hasLength(3), reason: 'B34: dau hu is Đậu hũ');
    }, relies: 'nothing in the app: the fridge shows the rows as they come.');

    guardFixed('B14',
        'tamarind ("Me") warns about nothing; a warning is in Vietnamese',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B14');
      await user.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'allergenId': 'sesame', 'name': 'Mè'},
            {'allergenId': 'peanut', 'name': 'Đậu phộng'},
          ]));
      final res = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Me'},
          {'ingredient': 'Dầu mè'},
          {'ingredient': 'Đậu phộng'},
        ],
      });
      final warnings = {
        for (final row in res.dataList)
          row['ingredient']: row['allergyWarning'],
      };
      expect(warnings['Me'], isNull);
      expect(warnings['Dầu mè'], 'Cảnh báo dị ứng: Mè');
      expect(warnings['Đậu phộng'], 'Cảnh báo dị ứng: Đậu phộng');

      final other = await be.newUser(name: 'FE IT Pin B14 Me');
      await other.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'allergenId': 'sesame', 'name': 'Mè'},
          ]));
      final sesame = await other.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Mè'},
        ],
      });
      expect(sesame.dataList.single['allergyWarning'], 'Cảnh báo dị ứng: Mè',
          reason: 'sesame itself still warns');
    },
        relies: 'the fridge screen shows the names after "Cảnh báo dị ứng:" as '
            'they come.');

    guardFixed('B17', 'a comment has no updatedAt until it is edited',
        () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      final rootId = root.dataMap['id'];
      final reply = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': rootId});
      final second = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Hai', 'parentId': reply.dataMap['id']});
      await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Ba', 'parentId': rootId});

      void noneEdited(List<Map<String, dynamic>> comments) {
        for (final comment in comments) {
          expect(comment['updatedAt'], isNull, reason: '${comment['content']}');
        }
      }

      final replies =
          await me.raw('GET', '/posts/$id/comments/$rootId/replies');
      expect(replies.dataList, hasLength(3));
      noneEdited(replies.dataList);

      await me.raw('DELETE', '/comments/${second.dataMap['id']}');
      final list = await me.raw('GET', '/posts/$id/comments');
      noneEdited(list.dataList);
      noneEdited((list.dataList.single['replies'] as List<dynamic>)
          .cast<Map<String, dynamic>>());
    }, relies: 'the app shows "(đã sửa)" whenever `updatedAt` is set.');

    guardFixed('B23', 'the reset route answers with a code and Vietnamese',
        () async {
      final res = await rawRequest('POST', '/auth/reset-password',
          data: {'resetToken': 'khong-co', 'newPassword': randomPassword()});
      expect(res.status, 400);
      expect(res.json['code'], 'invalid_code');
      expect(res.json['message'], isVietnamese);
    }, relies: 'AuthErrors.localize no longer reads a code out of `message`.');

    guardFixed('B31', 'a large target is within reach: portions follow it',
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
      expect(days, isNotEmpty);
      for (final day in days) {
        final total = day['totalCalories'] as num;
        expect(total, greaterThan(target * 0.85));
        expect(total, lessThan(target * 1.15));
        final sum = (day['meals'] as Map).values.fold<num>(
            0,
            (sum, meal) =>
                sum +
                ((meal as Map)['calories'] as num) * (meal['portion'] as num));
        expect(sum, closeTo(total, 2),
            reason: '`calories` is for one portion, the total for all of them');
      }
    },
        relies: 'the planner multiplies `calories` by `portion`, and shows '
            '"2,35 phần" as it comes.');

    guardFixed('B33', 'a dish with no prepMinutes stays without', () async {
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
      expect(meal['prepMinutes'], isNull);
    }, relies: 'a dish typed in shows no time.');

    guardFixed('B35', 'the errors of the BE are not garbled', () async {
      final wrong = await rawRequest('POST', '/auth/login',
          data: {'email': me.email, 'password': randomPassword()});
      expect(wrong.status, 401);
      final taken = await rawRequest('POST', '/auth/register', data: {
        'fullName': 'FE IT',
        'email': me.email,
        'password': randomPassword(),
      });
      expect(taken.status, 409);
      final other = await be.newUser(name: 'FE IT Pin B35');
      final notMine = await me.raw('PUT', '/users/${other.id}', data: {
        'fullName': 'x',
      });
      expect(notMine.status, greaterThanOrEqualTo(400));
      final noUser = await rawRequest('GET', '/posts/000000000000000000000000',
          token: me.token);
      expect(noUser.status, 404);
      final badToken = await rawRequest('GET', '/users/me', token: 'khong-co');
      expect(badToken.status, 401);
      for (final res in [wrong, taken, notMine, noUser, badToken]) {
        final message = res.json['message'] as String? ?? '';
        expect(message, isVietnamese);
        expect(_garbled.hasMatch(message), isFalse, reason: message);
      }
    },
        relies: 'mapDioException would drop such a message for a sentence by '
            'status, so the member loses what the BE meant to say.');

    guardFixed('B36', 'POST metrics checks what it takes, and needs a profile',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B36');
      final noProfile = await user
          .raw('POST', '/health-profile/me/metrics', data: {'weightKg': 70});
      expect(noProfile.status, 404);
      expect(noProfile.json['code'], 'not_found');
      expect(noProfile.json['message'], isVietnamese);
      final none = await user.raw('GET', '/health-profile/me/metrics');
      expect(none.dataList, isEmpty, reason: 'no made-up row');

      await user.raw('PUT', '/health-profile/me', data: profileBody());
      for (final bad in const <Map<String, Object?>>[
        {'weightKg': -5},
        {'weightKg': 0},
        {'weightKg': 301},
        {'waistCm': -3},
        {'bodyFatPct': 500},
        {},
      ]) {
        final res =
            await user.raw('POST', '/health-profile/me/metrics', data: bad);
        expect(res.status, 400, reason: '$bad');
        expect(res.json['message'], isVietnamese);
      }
      final profile = await user.raw('GET', '/health-profile/me');
      expect(profile.dataMap['weightKg'], 66);
      final rows = await user.raw('GET', '/health-profile/me/metrics');
      expect(rows.dataList, hasLength(1), reason: 'the one of the first PUT');
    },
        relies: 'logBodyMeasurement sends the weight as it is; the check-in '
            'sheet keeps its own narrower range.');

    guardFixed('B37',
        'POST metrics keeps `source`; a row from a profile save says `profile`',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B37 Source');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final logged = await user.raw('POST', '/health-profile/me/metrics',
          data: {'weightKg': 90, 'source': 'check_in'});
      expect(logged.status, 201);
      expect(logged.dataMap['source'], 'check_in');
      final rows = await user.raw('GET', '/health-profile/me/metrics');
      expect(rows.dataList.map((r) => r['source']),
          containsAll(['check_in', 'profile']));
    },
        relies: 'a row with `source: profile` reads "Từ Hồ sơ sức khoẻ" on the '
            'weight history.');

    guardFixed('B37', 'POST metrics moves the target and the week, one row',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B37 Fixed');
      final saved =
          await user.raw('PUT', '/health-profile/me', data: profileBody());
      final target = saved.dataMap['targetCalories'] as num;
      await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      await user
          .raw('POST', '/health-profile/me/metrics', data: {'weightKg': 90});
      final profile = await user.raw('GET', '/health-profile/me');
      expect(profile.dataMap['weightKg'], 90);
      final moved = profile.dataMap['targetCalories'] as num;
      expect(moved, greaterThan(target));
      expect(profile.dataMap['activityLevel'], 'light');
      final plan = await user.raw('GET', '/meal-plans/current');
      expect((plan.dataMap['dailyTargets'] as Map)['calories'], moved);
      final rows = await user.raw('GET', '/health-profile/me/metrics');
      expect(rows.dataList.where((r) => r['weightKg'] == 90), hasLength(1));
    }, relies: 'logBodyMeasurement sends no PUT after the POST.');

    guardFixed('B38', 'a second add without a quantity keeps the amount',
        () async {
      final user = await be.newUser(name: 'FE IT Pin B38');
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Cà chua', 'quantity': 300, 'unit': 'g'},
        ],
      });
      final again = await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'ca chua'},
        ],
      });
      expect(again.dataList.single['quantity'], 300);
      final list = await user.raw('GET', '/users/me/ingredients');
      expect(list.dataList.single['quantity'], 300);
      expect(list.dataList.single['unit'], 'g');
    },
        relies:
            'RemotePantryApiService.addItems reads nothing before the POST.');

    guardFixed(
        'B39',
        'a reply to a reply joins the top-level comment; deleting the root '
            'takes all of it', () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      final rootId = root.dataMap['id'];
      final reply = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': rootId});
      final nested = await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Hai', 'parentId': reply.dataMap['id']});
      expect(nested.dataMap['parentId'], rootId);
      final replies =
          await me.raw('GET', '/posts/$id/comments/$rootId/replies');
      expect(replies.dataList, hasLength(2));

      await me.raw('DELETE', '/comments/$rootId');
      final post = await me.raw('GET', '/posts/$id');
      expect(post.dataMap['commentCount'], 0);
      final list = await me.raw('GET', '/posts/$id/comments');
      expect(list.dataList, isEmpty);
    }, relies: 'the count on a post is what the BE says after a delete.');

    guardFixed('B40', 'the replies route checks the post id', () async {
      final id = await newPost(me);
      final root =
          await me.raw('POST', '/posts/$id/comments', data: {'content': 'Gốc'});
      await me.raw('POST', '/posts/$id/comments',
          data: {'content': 'Một', 'parentId': root.dataMap['id']});
      final other = await newPost(me);
      final res = await me.raw(
          'GET', '/posts/$other/comments/${root.dataMap['id']}/replies');
      expect(res.status, 404);
    }, relies: 'nothing in the app: it always asks with the right post.');

    guardFixed(
        'B41',
        'writes are checked: a recipe at -100 kcal, a slot that is not one, a '
            'beef dish, a source that is not one', () async {
      final recipe = await me.raw('POST', '/recipes', data: {
        'name': 'Rau xào',
        'calories': -100,
        'prepMinutes': 5,
        'ingredients': ['Rau'],
        'instructions': ['Nấu'],
      });
      expect(recipe.status, 400);
      expect(recipe.json['code'], 'invalid_calories');
      final prep = await me.raw('POST', '/recipes', data: {
        'name': 'Rau xào',
        'calories': 100,
        'prepMinutes': -5,
        'ingredients': ['Rau'],
        'instructions': ['Nấu'],
      });
      expect(prep.status, 400);
      expect(prep.json['code'], 'invalid_prep_minutes');

      final user = await be.newUser(name: 'FE IT Pin B41');
      await user.raw('PUT', '/health-profile/me', data: profileBody());
      final plan = await user.raw('POST', '/meal-plans/generate',
          data: {'startDate': _thisMonday});
      final slot = await user.raw('POST', '/meal-plans/current/meals', data: {
        'date': _today,
        'slot': 'khong-co-bua-nay',
        'name': 'Rau',
        'calories': 100,
      });
      expect(slot.status, 400);
      expect(slot.json['code'], 'invalid_slot');
      final beef = await user.raw('POST', '/meal-plans/current/meals', data: {
        'date': _today,
        'slot': 'lunch',
        'name': 'Thịt bò',
        'calories': 100,
      });
      expect(beef.status, 400);
      expect(beef.json['code'], 'not_vegan');
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
      expect(patched.status, 400);
      expect(patched.json['code'], 'invalid_source');
    }, relies: 'nothing in the app: it checks these before sending.');

    guardFixed(
        'B41', 'a recipe with beef in its name or ingredients is refused',
        () async {
      final named = await me.raw('POST', '/recipes', data: {
        'name': 'Thịt bò xào',
        'calories': 200,
        'prepMinutes': 5,
        'ingredients': ['Rau'],
        'instructions': ['Nấu'],
      });
      expect(named.status, 400);
      expect(named.json['message'], isVietnamese);
      final listed = await me.raw('POST', '/recipes', data: {
        'name': 'Rau xào',
        'calories': 200,
        'prepMinutes': 5,
        'ingredients': ['Rau', 'Thịt heo'],
        'instructions': ['Nấu'],
      });
      expect(listed.status, 400);
    }, relies: 'nothing in the app: it checks these before sending.');

    guardFixed('B68', 'an allergy named "Đậu nành" is saved as soy', () async {
      final user = await be.newUser(name: 'FE IT Pin B68');
      final res = await user.raw('PUT', '/health-profile/me',
          data: profileBody(allergies: [
            {'name': 'Đậu nành'},
            {'name': 'lá lốt'},
          ]));
      final allergies = (res.dataMap['allergies'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(allergies.map((a) => a['allergenId']), ['soy', null]);
      expect(allergies.last['name'], 'lá lốt');
    }, relies: 'the health form sends the id or the name the member typed.');
  });
}

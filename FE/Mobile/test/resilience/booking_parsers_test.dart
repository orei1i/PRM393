// test/resilience/booking_parsers_test.dart
// Booking fields that come in more than one shape: one odd row must not fail a
// whole plan or list once this module talks to the real BE.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';

void main() {
  group('a recipe of a plan day: instructions', () {
    PlanRecipeDto recipe(Object? instructions) => PlanRecipeDto.fromJson({
          'id': 'r1',
          'name': 'Bún riêu chay',
          'instructions': instructions,
        });

    test('text stays as it is', () {
      expect(recipe('1. Sơ chế').instructions, '1. Sơ chế');
    });

    test('the list a RecipeResponse sends becomes one line per step', () {
      expect(recipe(['Sơ chế.', 'Nấu.']).instructions, 'Sơ chế.\nNấu.');
    });

    test('anything else reads as none', () {
      expect(recipe(null).instructions, isNull);
      expect(recipe(12).instructions, isNull);
      expect(recipe({'a': 1}).instructions, isNull);
    });
  });

  group('who decided', () {
    EscrowHoldDto escrow(Object? by) =>
        EscrowHoldDto.fromJson({'id': 'eh', 'amount': 1, 'resolvedBy': by});
    ComplaintDto complaint(Object? by) =>
        ComplaintDto.fromJson({'id': 'cp', 'decidedBy': by});

    test('resolvedBy: a name, or { fullName }', () {
      expect(escrow('Quản trị viên').resolvedBy, 'Quản trị viên');
      expect(escrow({'fullName': 'Quản trị viên'}).resolvedBy, 'Quản trị viên');
    });

    test('decidedBy: a name, or { fullName }', () {
      expect(complaint('Quản trị viên').decidedBy, 'Quản trị viên');
      expect(complaint({'id': 'a', 'fullName': 'Quản trị viên'}).decidedBy,
          'Quản trị viên');
    });

    test('anything else reads as nobody', () {
      for (final odd in [null, 12, <Object?>[], <String, dynamic>{}]) {
        expect(escrow(odd).resolvedBy, isNull);
        expect(complaint(odd).decidedBy, isNull);
      }
    });
  });
}

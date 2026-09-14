import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';

class MockUserProfileRepository implements UserProfileRepository {
  @override
  UserProfile profileFor(String id, String name) => UserProfile(
    id: id,
    name: name,
    bio:
        'Finding joy in plants, one meal at a time. Home cook, weekend explorer, and a believer in small changes.',
    location: 'Ho Chi Minh City',
  );
}

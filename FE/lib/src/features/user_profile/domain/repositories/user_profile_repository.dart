import '../entities/user_profile.dart';

abstract interface class UserProfileRepository {
  UserProfile profileFor(String id, String name);
}

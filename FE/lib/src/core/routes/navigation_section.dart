import '../../features/auth/domain/entities/auth_session.dart';

/// Section ownership for tool/detail routes, independent of navigation history.
String navigationRoot(String path, UserRole role) {
  if (path == '/bmi') return '/planner';
  if (path == '/my-content' || path.startsWith('/edit/')) return '/profile';
  if (path == '/create') return '/community';
  if (path.startsWith('/post/') || path.startsWith('/video/')) {
    return switch (role) {
      UserRole.guest => '/explore',
      UserRole.member => '/community',
      UserRole.admin => '/admin/moderation',
    };
  }
  return path;
}

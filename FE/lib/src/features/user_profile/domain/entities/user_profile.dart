class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.bio,
    required this.location,
  });
  final String id, name, bio, location;
}

class UserContentSummary {
  const UserContentSummary({
    required this.posts,
    required this.videos,
    required this.comments,
  });
  final int posts, videos, comments;
}

enum ContentTab { posts, videos, comments }

enum VoteState { none, up, down }

class RecipePost {
  const RecipePost({
    required this.id,
    required this.authorId,
    required this.author,
    required this.title,
    required this.description,
    required this.category,
    required this.ingredients,
    required this.steps,
    this.minutes = 20,
    this.protein = 18,
    this.calories = 420,
    this.baseVotes = 0,
    this.art = 0,
    this.isVideo = false,
    this.hidden = false,
  });
  final String id, authorId, author, title, description, category;
  final List<String> ingredients, steps;
  final int minutes, protein, calories, baseVotes, art;
  final bool isVideo, hidden;

  RecipePost copyWith({
    String? title,
    String? description,
    String? category,
    List<String>? ingredients,
    List<String>? steps,
    bool? hidden,
  }) => RecipePost(
    id: id,
    authorId: authorId,
    author: author,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
    minutes: minutes,
    protein: protein,
    calories: calories,
    baseVotes: baseVotes,
    art: art,
    isVideo: isVideo,
    hidden: hidden ?? this.hidden,
  );
}

class CookingVideo {
  const CookingVideo({
    required this.post,
    this.duration = const Duration(minutes: 4, seconds: 32),
  });
  final RecipePost post;
  final Duration duration;
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.author,
    required this.text,
    this.parentId,
  });
  final String id, postId, authorId, author, text;
  final String? parentId;
  Comment copyWith({required String text}) => Comment(
    id: id,
    postId: postId,
    authorId: authorId,
    author: author,
    text: text,
    parentId: parentId,
  );
}

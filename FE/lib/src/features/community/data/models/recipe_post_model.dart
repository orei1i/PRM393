import '../../domain/entities/community_entities.dart';

class RecipePostModel {
  const RecipePostModel(this.json);
  final Map<String, Object?> json;

  RecipePost toEntity() => RecipePost(
    id: json['id']! as String,
    authorId: json['authorId']! as String,
    author: json['author']! as String,
    title: json['title']! as String,
    description: json['description']! as String,
    category: json['category']! as String,
    ingredients: List<String>.unmodifiable(
      (json['ingredients']! as List).cast<String>(),
    ),
    steps: List<String>.unmodifiable((json['steps']! as List).cast<String>()),
    minutes: json['minutes']! as int,
    protein: json['protein']! as int,
    calories: json['calories']! as int,
    baseVotes: json['votes']! as int,
    art: json['art']! as int,
    isVideo: json['video'] as bool? ?? false,
  );
}

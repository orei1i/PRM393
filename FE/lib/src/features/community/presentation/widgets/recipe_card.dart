import 'package:flutter/material.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/food_art.dart';
import '../../domain/entities/community_entities.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    required this.post,
    required this.votes,
    required this.saved,
    required this.onOpen,
    required this.onSave,
    super.key,
  });
  final RecipePost post;
  final int votes;
  final bool saved;
  final VoidCallback onOpen, onSave;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              children: [
                FoodArt(variant: post.art),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: StatusBadge(
                    post.isVideo ? 'COOK ALONG' : post.category.toUpperCase(),
                    icon: post.isVideo
                        ? Icons.play_arrow_rounded
                        : Icons.eco_outlined,
                  ),
                ),
                if (post.isVideo)
                  const Positioned.fill(
                    child: Center(
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 32,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: onOpen,
                child: Text(
                  post.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                post.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _meta(Icons.schedule, '${post.minutes} min'),
                  _meta(Icons.grass, '${post.protein}g protein'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$votes',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: onOpen,
                    child: Text(post.isVideo ? 'Watch demo' : 'View recipe'),
                  ),
                  IconButton(
                    onPressed: onSave,
                    tooltip: saved ? 'Unsave recipe' : 'Save recipe',
                    isSelected: saved,
                    selectedIcon: const Icon(Icons.bookmark),
                    icon: const Icon(Icons.bookmark_border),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _meta(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

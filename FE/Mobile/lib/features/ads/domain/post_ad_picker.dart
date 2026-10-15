// lib/features/ads/domain/post_ad_picker.dart
import '../../community/domain/entities/post.dart';
import '../../restaurant/domain/food_match.dart';
import '../data/models/ad_feed_item.dart';

/// Dishes and ingredients that make a post "about food", `|`-separated.
/// Matched as whole words with their accents, so "phố" (street) or "lâu"
/// (long) never count as "phở" or "lẩu". "chay" alone is not food talk:
/// every post says it.
const _foodTerms = 'bún|phở|cơm|cháo|lẩu|bánh|chè|xôi|gỏi|nộm|súp|mì|miến|'
    'hủ tiếu|nem|chả|canh chua|kho|xào|salad|đậu hũ|đậu phụ|tàu hũ|tempeh|'
    'nấm|rau|cà chua|cà ri|đậu xanh|đậu gà|đậu lăng|hạt sen|gạo lứt|'
    'yến mạch|sữa hạt|sữa chua|sữa đậu nành|nước cốt dừa';

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String text) =>
    text.toLowerCase().split(_separators).where((w) => w.isNotEmpty).toList();

final _foodTermWords = [for (final t in _foodTerms.split('|')) _words(t)];

/// True when [text] names a dish or an ingredient from the list above.
bool mentionsFood(String text) {
  final words = _words(text);
  for (final term in _foodTermWords) {
    for (var i = 0; i + term.length <= words.length; i++) {
      var hit = true;
      for (var j = 0; j < term.length && hit; j++) {
        hit = words[i + j] == term[j];
      }
      if (hit) return true;
    }
  }
  return false;
}

/// Whether a post's detail page may carry a sponsored store card at all:
/// published recipes and discussions (videos and held posts never do).
bool canCarrySponsoredCard(Post post) =>
    post.isPublished &&
    (post.type == PostType.recipe || post.type == PostType.discussion);

/// The one "Được tài trợ" card inside [post]'s detail page, or `null`.
///
/// The campaign whose store name or headline leads with the dish the post
/// talks about wins (matched like restaurant suggestions, see
/// [foodMatchScores]: "Bún riêu …" → Bún Riêu Chay Hạnh Tâm). Otherwise a
/// post that mentions food gets the nearest running campaign ([ads] arrive
/// nearest first); one that doesn't gets nothing.
AdFeedItemDto? sponsoredAdForPost(Post post, List<AdFeedItemDto> ads) {
  if (ads.isEmpty || !canCarrySponsoredCard(post)) return null;
  final texts = [post.title, post.body];
  AdFeedItemDto? best;
  var bestScore = 0;
  for (final ad in ads) {
    for (final food in [ad.restaurant.name, ad.headline]) {
      final score = foodMatchScores({ad.id: texts}, food)[ad.id] ?? 0;
      if (score > bestScore) {
        bestScore = score;
        best = ad;
      }
    }
  }
  if (best != null) return best;
  return mentionsFood('${post.title}\n${post.body}') ? ads.first : null;
}

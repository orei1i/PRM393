// lib/features/community/data/mock/community_mock_data.dart
import 'dart:math' as math;

import '../../../video/data/mock/video_mock_data.dart';

const _admin = {
  'id': 'u_admin',
  'fullName': 'Ban quản trị VeganLife',
  'isVerifiedChef': false
};
const _hoangNam = {
  'id': 'u_hoang_nam',
  'fullName': 'Hoàng Nam',
  'isVerifiedChef': false
};
const _ngocTram = {
  'id': 'u_ngoc_tram',
  'fullName': 'Ngọc Trâm',
  'isVerifiedChef': false
};
const _ducHuy = {
  'id': 'u_duc_huy',
  'fullName': 'Đức Huy',
  'isVerifiedChef': false
};
const _thuHa = {
  'id': 'u_thu_ha',
  'fullName': 'ThS. DD Phạm Thu Hà',
  'isVerifiedChef': true
};

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();

/// Newest first. `video` blocks point at [seedVideos].
List<Map<String, dynamic>> buildSeedPosts() => [
      {
        'id': 'p_pin_rules',
        'type': 'discussion',
        'author': _admin,
        'title': 'Nội quy cộng đồng & cách báo cáo bài sai thông tin',
        'body': 'Chia sẻ công thức, kinh nghiệm và câu hỏi về ăn chay — nhớ ghi nguồn khi nói về sức khoẻ. '
            'Thấy bài sai lệch, quảng cáo hay không thuần chay, bấm ⋯ › Báo cáo; đội kiểm duyệt xử lý trong 24 giờ.',
        'tags': <String>[],
        'likeCount': 312,
        'commentCount': 18,
        'isPinned': true,
        'createdAt': _ago(const Duration(days: 12)),
      },
      {
        'id': 'p_video_cha_lua',
        'type': 'video',
        'author': chefTam,
        'title': 'Chả lụa chay từ đậu hũ ky — không cần máy xay',
        'body':
            'Công thức mình bán ở quán 6 năm nay, chia sẻ cả nhà. AI đã tóm tắt sẵn nguyên liệu và từng bước nhé!',
        'tags': ['high_protein'],
        'coverSeed': 'cha-lua-chay',
        'likeCount': 842,
        'commentCount': 63,
        'createdAt': _ago(const Duration(hours: 2)),
        'video': {
          'id': 'vid_cha_lua',
          'durationSeconds': 724,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_bun_rieu',
        'type': 'recipe',
        'author': _hoangNam,
        'title': 'Bún riêu chay cà chua đậu hũ — nước dùng ngọt từ củ quả',
        'body': 'Nguyên liệu (4 người): 6 quả cà chua, 2 bìa đậu hũ, 300 g nấm rơm, 1 củ cải trắng, 2 bắp ngô, mắm ruốc chay.\n'
            '1. Hầm củ cải và bắp ngô 40 phút lấy nước dùng.\n'
            '2. Phi hành tím, xào cà chua đến khi sệt, cho vào nồi.\n'
            '3. Tán đậu hũ với nấm băm làm "riêu", thả từng muỗng khi nước sôi lăn tăn.\n'
            '4. Nêm muối, đường phèn; ăn kèm rau muống chẻ, kinh giới.',
        'tags': ['low_sodium', 'seasonal'],
        'coverSeed': 'bun-rieu-chay',
        'likeCount': 214,
        'commentCount': 27,
        'createdAt': _ago(const Duration(hours: 5)),
      },
      {
        'id': 'p_b12',
        'type': 'discussion',
        'author': _ngocTram,
        'title': 'Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?',
        'body':
            'Mình ăn chay trường được 3 tuần, hay bị mệt buổi chiều. Mọi người bổ sung B12 bằng viên uống hay thực phẩm tăng cường? '
                'Có cần xét nghiệm trước không ạ?',
        'tags': <String>[],
        'likeCount': 46,
        'commentCount': 31,
        'createdAt': _ago(const Duration(hours: 8)),
      },
      {
        'id': 'p_video_meal_prep',
        'type': 'video',
        'author': bepNhaMay,
        'title': 'Meal prep 5 hộp cơm chay cho cả tuần với 150.000đ',
        'body':
            'Đi chợ một lần, nấu 90 phút, cả tuần không phải nghĩ trưa nay ăn gì.',
        'tags': ['high_fiber', 'whole_food'],
        'coverSeed': 'meal-prep-5-hop',
        'likeCount': 1290,
        'commentCount': 88,
        'createdAt': _ago(const Duration(days: 1, hours: 3)),
        'video': {
          'id': 'vid_meal_prep',
          'durationSeconds': 572,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_sua_chua_dua',
        'type': 'recipe',
        'author': thaoVy,
        'title': 'Sữa chua dừa tự làm, lên men 8 tiếng',
        'body': '400 ml nước cốt dừa + 1 muỗng bột năng + men vi sinh (2 viên). Nấu sệt nhẹ, để nguội 40 °C, '
            'trộn men, ủ nồi cơm ở chế độ giữ ấm (mở nắp hé) 8 tiếng. Để lạnh 4 tiếng trước khi ăn.',
        'tags': ['whole_food'],
        'coverSeed': 'sua-chua-dua',
        'likeCount': 167,
        'commentCount': 12,
        'createdAt': _ago(const Duration(days: 1, hours: 9)),
      },
      {
        'id': 'p_quan_chay_q9',
        'type': 'discussion',
        'author': _ducHuy,
        'title':
            'Quán chay ngon quanh khu Công nghệ cao Q.9? Ngân sách 40k/bữa',
        'body':
            'Mình mới chuyển công tác lên Q.9, cần vài quán cơm chay bình dân, có món nhiều đạm càng tốt. Cảm ơn cả nhà!',
        'tags': <String>[],
        'likeCount': 23,
        'commentCount': 19,
        'createdAt': _ago(const Duration(days: 2)),
      },
      {
        'id': 'p_video_sua_hat',
        'type': 'video',
        'author': thaoVy,
        'title': 'Sữa hạt điều yến mạch 5 phút, không cần máy làm sữa',
        'body': 'Bữa sáng 5 phút cho ngày bận rộn.',
        'tags': ['quick'],
        'coverSeed': 'sua-hat-dieu',
        'likeCount': 376,
        'commentCount': 21,
        'createdAt': _ago(const Duration(days: 2, hours: 6)),
        'video': {
          'id': 'vid_sua_hat',
          'durationSeconds': 251,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_dau_hu_sot_ca',
        'type': 'recipe',
        'author': bepNhaMay,
        'title': 'Đậu hũ sốt cà chua kiểu Bắc — 15 phút',
        'body':
            'Rán vàng 2 bìa đậu, xào 3 quả cà chua với hành lá và chút nước tương, cho đậu vào om 5 phút. '
                'Mẹo: thêm 1 thìa tương cà để sốt đậm màu.',
        'tags': ['quick', 'high_protein'],
        'coverSeed': 'dau-hu-sot-ca',
        'likeCount': 98,
        'commentCount': 6,
        'createdAt': _ago(const Duration(days: 3)),
      },
      {
        'id': 'p_dam_thuc_vat',
        'type': 'discussion',
        'author': _thuHa,
        'title': '5 nguồn đạm thực vật rẻ mà chợ nào cũng có',
        'body': 'Đậu hũ (8 g/100 g), đậu xanh nguyên vỏ (24 g), đậu phộng (26 g), mè đen (18 g) và tàu hũ ky (45 g khô). '
            'Kết hợp ngũ cốc nguyên hạt trong ngày để đủ axit amin thiết yếu. Nguồn: Bảng thành phần thực phẩm Việt Nam (Viện Dinh dưỡng).',
        'tags': ['high_protein'],
        'likeCount': 521,
        'commentCount': 44,
        'createdAt': _ago(const Duration(days: 3, hours: 7)),
      },
      {
        'id': 'p_com_chien_hat_sen',
        'type': 'recipe',
        'author': _hoangNam,
        'title': 'Cơm chiên hạt sen thập cẩm',
        'body':
            'Cơm nguội 2 chén, hạt sen 100 g, cà rốt, đậu Hà Lan, nấm đông cô. Chiên lửa lớn, nêm hạt nêm nấm.',
        'tags': <String>[],
        'coverSeed': 'com-chien-hat-sen',
        'likeCount': 64,
        'commentCount': 4,
        'createdAt': _ago(const Duration(days: 4)),
      },
      {
        'id': 'p_me_banh_xeo',
        'type': 'video',
        'author': currentUserAuthor,
        'title': 'Bánh xèo chay nhân nấm — video đầu tay của mình',
        'body': 'Lần đầu quay video nấu ăn, mọi người góp ý giúp mình nha!',
        'tags': <String>[],
        'coverSeed': 'banh-xeo-chay',
        'likeCount': 12,
        'commentCount': 3,
        'createdAt': _ago(const Duration(days: 5)),
        'video': {
          'id': 'vid_banh_xeo',
          'durationSeconds': 486,
          'aiStatus': 'failed'
        },
      },
      {
        'id': 'p_me_hoi_tempeh',
        'type': 'discussion',
        'author': currentUserAuthor,
        'title': 'Mua tempeh ở đâu tại TP.HCM?',
        'body':
            'Mình thấy tempeh trong thực đơn AI gợi ý nhưng chưa biết mua ở đâu, ai biết chỉ mình với.',
        'tags': <String>[],
        'likeCount': 8,
        'commentCount': 5,
        'createdAt': _ago(const Duration(days: 6)),
      },
      // Short clips for the Reels strip: uploaded files (`mediaUrl`, public
      // sample clips here) with their AI recipe ready.
      {
        'id': 'p_reel_goi_cuon',
        'type': 'video',
        'author': chefChau,
        'title':
            'Gỏi cuốn chay 60 giây: cuốn chặt tay mà không rách bánh tráng',
        'body':
            'Mẹo nhỏ: nhúng bánh tráng thật nhanh, xếp rau trước rồi mới đến đậu hũ.',
        'tags': ['quick'],
        'coverSeed': 'goi-cuon-chay',
        'likeCount': 655,
        'commentCount': 14,
        'createdAt': _ago(const Duration(days: 7)),
        'mediaType': 'Video',
        'mediaUrl': sampleVideoUrlC,
        'video': {
          'id': 'vid_goi_cuon',
          'durationSeconds': 58,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_reel_nam_kho_tieu',
        'type': 'video',
        'author': bepNhaMay,
        'title': 'Nấm kho tiêu kiểu miền Tây, đưa cơm cả nhà',
        'body':
            'Nấm bào ngư xé sợi kho nước dừa với tiêu xanh. Xem 1 phút là nấu được.',
        'tags': ['whole_food'],
        'coverSeed': 'nam-kho-tieu',
        'likeCount': 402,
        'commentCount': 9,
        'createdAt': _ago(const Duration(days: 8)),
        'mediaType': 'Video',
        'mediaUrl': sampleVideoUrlB,
        'video': {
          'id': 'vid_nam_kho_tieu',
          'durationSeconds': 64,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_reel_che_dau_xanh',
        'type': 'video',
        'author': thaoVy,
        'title': 'Chè đậu xanh nước cốt dừa, nấu bằng nồi cơm điện',
        'body':
            'Không cần canh bếp: ngâm đậu, cho vào nồi cơm điện, 40 phút là xong.',
        'tags': <String>[],
        'coverSeed': 'che-dau-xanh',
        'likeCount': 288,
        'commentCount': 7,
        'createdAt': _ago(const Duration(days: 9)),
        'mediaType': 'Video',
        'mediaUrl': sampleVideoUrlA,
        'video': {
          'id': 'vid_che_dau_xanh',
          'durationSeconds': 45,
          'aiStatus': 'ready'
        },
      },
      {
        'id': 'p_reel_salad_tempeh',
        'type': 'video',
        'author': chefTam,
        'title': 'Salad tempeh áp chảo sốt mè rang cho bữa trưa văn phòng',
        'body':
            'Tempeh áp chảo 4 phút mỗi mặt, trộn rau mầm và sốt mè. Mang đi làm vẫn giòn.',
        'tags': ['high_protein'],
        'coverSeed': 'salad-tempeh',
        'likeCount': 517,
        'commentCount': 11,
        'createdAt': _ago(const Duration(days: 10)),
        'mediaType': 'Video',
        'mediaUrl': sampleVideoUrlC,
        'video': {
          'id': 'vid_salad_tempeh',
          'durationSeconds': 52,
          'aiStatus': 'ready'
        },
      },
      // Held by the AI pre-screen; same ids and titles as the web console.
      {
        'id': 'p_me_pending_celery',
        'type': 'discussion',
        'author': currentUserAuthor,
        'title': 'Nước ép cần tây có chữa khỏi tiểu đường không?',
        'body':
            'Mình đọc được là uống nước ép cần tây mỗi sáng chữa khỏi tiểu đường type 2. '
                'Có ai thử chưa, có nguồn nghiên cứu nào không ạ?',
        'tags': <String>[],
        'likeCount': 0,
        'commentCount': 0,
        'status': 'Pending',
        'createdAt': _ago(const Duration(hours: 20)),
      },
      {
        'id': 'p_me_rejected_detox',
        'type': 'discussion',
        'author': currentUserAuthor,
        'title': 'Trà detox giảm cân thần tốc 7 ngày',
        'body':
            'Trà thảo mộc giúp mình xuống 5 kg trong 7 ngày, ai cần công thức thì nhắn mình nhé.',
        'tags': <String>[],
        'likeCount': 0,
        'commentCount': 0,
        'status': 'Rejected',
        'rejectionReason':
            'Bài khẳng định hiệu quả giảm cân chưa được kiểm chứng. Vui lòng bỏ cam kết và ghi nguồn rồi gửi lại.',
        'createdAt': _ago(const Duration(days: 3, hours: 2)),
      },
    ];

const Map<String, List<Map<String, Object>>> seedComments = {
  'p_b12': [
    {
      'author': _thuHa,
      'text':
          'Nên dùng B12 dạng cyanocobalamin 250 µg/ngày hoặc 2.500 µg/tuần. Xét nghiệm nếu mệt kéo dài nhé.',
      'minutesAgo': 300
    },
    {
      'author': _hoangNam,
      'text':
          'Mình uống sữa đậu nành có bổ sung B12, kèm viên uống 2 lần/tuần.',
      'minutesAgo': 240
    },
    {
      'author': _ducHuy,
      'text':
          'Mệt buổi chiều có khi do thiếu sắt nữa, bạn thử thêm đậu lăng + rau có vitamin C.',
      'minutesAgo': 95
    },
    // Lê Quang Tâm's comments fill his "Bình luận" tab (Minh Anh has none,
    // so hers starts empty).
    {
      'author': chefTam,
      'text':
          'Ngoài B12, bạn nhớ ăn đủ đạm từ đậu hũ, tempeh và các loại đậu nhé. Mệt kéo dài thì nên đi khám.',
      'minutesAgo': 60
    },
  ],
  'p_dau_hu_sot_ca': [
    {
      'author': chefTam,
      'text':
          'Mẹo nhỏ: ướp đậu với chút nước tương 10 phút trước khi rán, sốt sẽ thấm hơn.',
      'minutesAgo': 2400
    },
  ],
  'p_video_cha_lua': [
    {
      'author': _ngocTram,
      'text': 'Làm theo thành công ngay lần đầu, dai thật sự!',
      'minutesAgo': 70
    },
    {
      'author': bepNhaMay,
      'text': 'Thay bột năng bằng bột khoai mì được không anh?',
      'minutesAgo': 40
    },
  ],
};

/// Commenters for the generated part of each thread (never the signed-in
/// member, so "my" comments are only the ones written in this session).
const _commenters = <Map<String, Object>>[
  _hoangNam,
  _ngocTram,
  _ducHuy,
  {'id': 'u_lan_anh', 'fullName': 'Lan Anh', 'isVerifiedChef': false},
  {'id': 'u_quoc_bao', 'fullName': 'Quốc Bảo', 'isVerifiedChef': false},
  {'id': 'u_my_duyen', 'fullName': 'Mỹ Duyên', 'isVerifiedChef': false},
  {'id': 'u_tuan_kiet', 'fullName': 'Tuấn Kiệt', 'isVerifiedChef': false},
  {'id': 'u_bich_ngoc', 'fullName': 'Bích Ngọc', 'isVerifiedChef': false},
  {'id': 'u_van_khoa', 'fullName': 'Văn Khoa', 'isVerifiedChef': false},
  {'id': 'u_thanh_truc', 'fullName': 'Thanh Trúc', 'isVerifiedChef': false},
  {'id': 'u_minh_khang', 'fullName': 'Minh Khang', 'isVerifiedChef': false},
];

const _recipeReplies = [
  'Cuối tuần này mình làm thử, cả nhà chắc thích lắm.',
  'Công thức dễ làm mà nhìn ngon quá, cảm ơn bạn!',
  'Mình làm theo rồi, vị vừa ăn. Lần sau sẽ giảm muối một chút.',
  'Món này để tủ lạnh được mấy ngày vậy bạn?',
  'Đã lưu, mai đi chợ mua nguyên liệu luôn.',
  'Nấu sẵn mang đi làm buổi trưa có ổn không nhỉ?',
  'Bé nhà mình 5 tuổi ăn cũng khen ngon.',
  'Thay đường trắng bằng đường thốt nốt được không bạn?',
  'Lần đầu nấu chay mà thành công, cảm ơn công thức chi tiết.',
  'Nguyên liệu dễ kiếm, chợ gần nhà đều có.',
  'Một phần khoảng bao nhiêu kcal vậy bạn?',
  'Mình thêm ít nấm đông cô, thơm hơn hẳn.',
  'Nhìn hấp dẫn quá, đói bụng luôn rồi.',
  'Các bước ghi rõ ràng, người mới như mình cũng làm được.',
];

const _videoReplies = [
  'Video quay rõ từng bước, xem một lần là hiểu.',
  'Phần AI tóm tắt nguyên liệu tiện ghê, khỏi phải tua lại.',
  'Giọng hướng dẫn dễ nghe, mong có thêm nhiều video nữa.',
  'Xem xong làm theo liền, ra y như trong video.',
  'Cho mình hỏi dùng chảo chống dính loại nào vậy?',
  'Đoạn cuối trình bày đẹp quá, học được nhiều mẹo.',
  'Mình đã chia sẻ video cho nhóm ăn chay ở công ty.',
  'Tua theo từng bước rất tiện, cảm ơn VeganLife.',
  'Có thể làm phiên bản ít dầu hơn không ạ?',
  'Đã lưu, cuối tuần sẽ thử làm.',
  'Nhìn đơn giản mà ngon, hợp với người bận rộn như mình.',
  'Lần đầu xem video của bạn mà thích luôn, theo dõi rồi nha.',
];

const _discussionReplies = [
  'Cảm ơn bạn đã chia sẻ, thông tin rất hữu ích.',
  'Mình cũng đang quan tâm chủ đề này, theo dõi bài.',
  'Bài viết hay, mình lưu lại để đọc kỹ hơn.',
  'Ai có thêm kinh nghiệm thì chia sẻ cho mọi người với nhé.',
  'Mình ăn chay được 2 năm, thấy quan trọng nhất là ăn đa dạng.',
  'Cộng đồng ở đây dễ thương ghê, hỏi gì cũng có người trả lời.',
  'Bạn thử đặt lịch với chuyên gia dinh dưỡng trên app, mình được tư vấn kỹ lắm.',
  'Đọc bình luận của mọi người học thêm được nhiều điều.',
  'Thông tin có nguồn rõ ràng nên mình yên tâm hơn.',
  'Hóng thêm chia sẻ từ mọi người.',
  'Đồng ý, ăn chay cũng cần tìm hiểu kỹ như mọi chế độ ăn khác.',
  'Mình cũng từng thắc mắc y hệt, giờ thì rõ rồi.',
];

/// Generated replies that, with [seedComments], make each mock thread as long
/// as the post's `commentCount`. Same output for the same [postId]; no two
/// neighbours share an author or a text, and [postAuthorId] never comments.
List<Map<String, Object>> buildFillerComments({
  required String postId,
  required String postType,
  required String postAuthorId,
  required int count,
}) {
  if (count <= 0) return const [];
  final texts = switch (postType) {
    'recipe' => _recipeReplies,
    'video' => _videoReplies,
    _ => _discussionReplies,
  };
  final people = _commenters.where((a) => a['id'] != postAuthorId).toList();
  final random = math.Random(
      postId.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x7fffffff));

  final result = <Map<String, Object>>[];
  var deck = <String>[];
  for (var i = 0; i < count; i++) {
    if (deck.isEmpty) {
      deck = List.of(texts)..shuffle(random);
      // Don't repeat the last text across reshuffles.
      if (result.isNotEmpty && deck.last == result.last['text']) {
        deck.insert(0, deck.removeLast());
      }
    }
    var author = people[random.nextInt(people.length)];
    if (result.isNotEmpty && author == result.last['author']) {
      author = people[(people.indexOf(author) + 1) % people.length];
    }
    result.add({'author': author, 'text': deck.removeLast()});
  }
  return result;
}

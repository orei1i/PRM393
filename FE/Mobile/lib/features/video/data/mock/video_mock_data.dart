// lib/features/video/data/mock/video_mock_data.dart
//
// Seed cooking videos (wire format). Sample clips are public Flutter test
// videos — swap for Cloudinary URLs once the backend serves real uploads.

const sampleVideoUrlA =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
const sampleVideoUrlB =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

const chefTam = {
  'id': 'u_chef_tam',
  'fullName': 'Lê Quang Tâm',
  'isVerifiedChef': true
};
const chefChau = {
  'id': 'u_chef_chau',
  'fullName': 'Tôn Nữ Minh Châu',
  'isVerifiedChef': true
};
const bepNhaMay = {
  'id': 'u_bep_may',
  'fullName': 'Bếp Chay Nhà Mây',
  'isVerifiedChef': false
};
const thaoVy = {
  'id': 'u_thao_vy',
  'fullName': 'Thảo Vy',
  'isVerifiedChef': false
};

/// The signed-in demo member (see MockAuthApiService).
const currentUserAuthor = {
  'id': 'u_me',
  'fullName': 'Minh Anh',
  'isVerifiedChef': false
};

final List<Map<String, dynamic>> seedVideos = [
  {
    'id': 'vid_cha_lua',
    'title': 'Chả lụa chay từ đậu hũ ky — không cần máy xay',
    'author': chefTam,
    'coverSeed': 'cha-lua-chay',
    'videoUrl': sampleVideoUrlA,
    'durationSeconds': 724,
    'aiStatus': 'ready',
    'summary':
        'Chả lụa chay dai, thơm nhờ đậu hũ ky và nấm đông cô, gói lá chuối rồi hấp 35 phút. '
            'Khoảng 14 g đạm mỗi khẩu phần — hợp ăn sáng hoặc kẹp bánh mì.',
    'servings': 4,
    'totalMinutes': 45,
    'kcalPerServing': 210,
    'ingredients': [
      {'name': 'Đậu hũ ky khô', 'quantity': '200 g', 'atSecond': 35},
      {'name': 'Bột năng', 'quantity': '3 muỗng canh', 'atSecond': 58},
      {'name': 'Nấm đông cô ngâm', 'quantity': '5 cái', 'atSecond': 80},
      {'name': 'Tiêu xay', 'quantity': '1 muỗng cà phê', 'atSecond': 95},
      {
        'name': 'Hạt nêm nấm',
        'quantity': '1 muỗng cà phê',
        'atSecond': 99,
        'uncertain': true
      },
      {'name': 'Nước tương', 'quantity': '2 muỗng canh', 'atSecond': 102},
      {'name': 'Lá chuối', 'quantity': '2 lá', 'atSecond': 150},
    ],
    'steps': [
      {
        'index': 1,
        'text':
            'Ngâm đậu hũ ky trong nước ấm 10 phút cho mềm rồi vắt thật ráo.',
        'atSecond': 40
      },
      {
        'index': 2,
        'text':
            'Xé nhỏ đậu hũ ky, trộn với bột năng, nước tương, tiêu và hạt nêm.',
        'atSecond': 90
      },
      {
        'index': 3,
        'text':
            'Băm nhuyễn nấm đông cô, trộn đều vào hỗn hợp, nhồi 3 phút cho dẻo.',
        'atSecond': 140
      },
      {
        'index': 4,
        'text': 'Gói chặt bằng lá chuối thành khối tròn, cột dây 3–4 vòng.',
        'atSecond': 230
      },
      {
        'index': 5,
        'text': 'Hấp 35 phút, để nguội hẳn rồi mới cắt lát để chả không bị bở.',
        'atSecond': 400
      },
    ],
    'transcript': [
      {
        'atSecond': 0,
        'text':
            'Chào cả nhà, hôm nay Tâm làm chả lụa chay mà không cần máy xay nhé.'
      },
      {
        'atSecond': 35,
        'text':
            'Mình dùng 200 gram đậu hũ ky khô, ngâm nước ấm khoảng mười phút.'
      },
      {'atSecond': 58, 'text': 'Thêm ba muỗng canh bột năng để chả có độ dai.'},
      {
        'atSecond': 95,
        'text':
            'Một muỗng cà phê tiêu, một muỗng… hạt nêm nấm, rồi hai muỗng nước tương.'
      },
      {
        'atSecond': 230,
        'text':
            'Gói thật chặt tay, lá chuối hơ qua lửa cho dẻo sẽ không bị rách.'
      },
      {
        'atSecond': 400,
        'text': 'Hấp ba mươi lăm phút. Nhớ để nguội hẳn rồi mới cắt nha.'
      },
    ],
  },
  {
    'id': 'vid_meal_prep',
    'title': 'Meal prep 5 hộp cơm chay cho cả tuần với 150.000đ',
    'author': bepNhaMay,
    'coverSeed': 'meal-prep-5-hop',
    'videoUrl': sampleVideoUrlB,
    'durationSeconds': 572,
    'aiStatus': 'ready',
    'summary':
        'Nấu một lần trong 90 phút cho 5 bữa trưa: cơm gạo lứt, tempeh áp chảo, đậu gà rang và rau củ nướng. '
            'Bảo quản ngăn mát 4 ngày, hộp thứ 5 để ngăn đá.',
    'servings': 5,
    'totalMinutes': 90,
    'kcalPerServing': 540,
    'ingredients': [
      {'name': 'Gạo lứt', 'quantity': '500 g', 'atSecond': 22},
      {'name': 'Tempeh', 'quantity': '300 g', 'atSecond': 61},
      {'name': 'Đậu gà luộc', 'quantity': '400 g', 'atSecond': 98},
      {'name': 'Bí đỏ', 'quantity': '400 g', 'atSecond': 140},
      {'name': 'Bông cải xanh', 'quantity': '1 cây', 'atSecond': 152},
      {
        'name': 'Sốt mè rang',
        'quantity': '5 muỗng canh',
        'atSecond': 300,
        'uncertain': true
      },
    ],
    'steps': [
      {
        'index': 1,
        'text': 'Vo và ngâm gạo lứt 30 phút, nấu với tỉ lệ 1 gạo : 1,6 nước.',
        'atSecond': 22
      },
      {
        'index': 2,
        'text':
            'Cắt tempeh lát 1 cm, áp chảo với nước tương và tỏi đến khi vàng hai mặt.',
        'atSecond': 61
      },
      {
        'index': 3,
        'text': 'Rang đậu gà với bột ớt và muối đến khi giòn.',
        'atSecond': 98
      },
      {
        'index': 4,
        'text': 'Nướng bí đỏ và bông cải ở 200 °C trong 20 phút.',
        'atSecond': 140
      },
      {
        'index': 5,
        'text': 'Chia đều vào 5 hộp, rưới sốt mè khi ăn.',
        'atSecond': 300
      },
    ],
    'transcript': [
      {
        'atSecond': 0,
        'text': 'Một trăm năm mươi nghìn cho năm hộp cơm, mình làm thử nha.'
      },
      {
        'atSecond': 22,
        'text': 'Gạo lứt nửa ký, ngâm ba mươi phút trước khi nấu.'
      },
      {'atSecond': 61, 'text': 'Tempeh ba trăm gram, cắt lát cỡ một phân.'},
      {'atSecond': 300, 'text': 'Sốt mè thì mỗi hộp chừng một muỗng thôi.'},
    ],
  },
  {
    'id': 'vid_sua_hat',
    'title': 'Sữa hạt điều yến mạch 5 phút, không cần máy làm sữa',
    'author': thaoVy,
    'coverSeed': 'sua-hat-dieu',
    'videoUrl': sampleVideoUrlA,
    'durationSeconds': 251,
    'aiStatus': 'ready',
    'summary':
        'Xay hạt điều đã ngâm với yến mạch và chà là, lọc qua túi vải. Uống trong 2 ngày.',
    'servings': 3,
    'totalMinutes': 10,
    'kcalPerServing': 160,
    'ingredients': [
      {'name': 'Hạt điều sống', 'quantity': '80 g', 'atSecond': 15},
      {'name': 'Yến mạch cán dẹt', 'quantity': '30 g', 'atSecond': 28},
      {'name': 'Chà là', 'quantity': '3 quả', 'atSecond': 40},
      {'name': 'Nước lọc', 'quantity': '800 ml', 'atSecond': 52},
    ],
    'steps': [
      {
        'index': 1,
        'text': 'Ngâm hạt điều 4 tiếng (hoặc nước sôi 20 phút).',
        'atSecond': 15
      },
      {
        'index': 2,
        'text': 'Xay hạt điều, yến mạch, chà là với 800 ml nước trong 60 giây.',
        'atSecond': 52
      },
      {
        'index': 3,
        'text': 'Lọc qua túi vải, giữ lạnh và lắc đều trước khi uống.',
        'atSecond': 120
      },
    ],
    'transcript': [
      {
        'atSecond': 0,
        'text': 'Hôm nay Vy làm sữa hạt điều siêu nhanh cho bữa sáng.'
      },
      {'atSecond': 52, 'text': 'Cho hết vào máy xay với tám trăm ml nước.'},
    ],
  },
  {
    'id': 'vid_banh_xeo',
    'title': 'Bánh xèo chay nhân nấm — video đầu tay của mình',
    'author': currentUserAuthor,
    'coverSeed': 'banh-xeo-chay',
    'videoUrl': sampleVideoUrlB,
    'durationSeconds': 486,
    'aiStatus': 'failed',
    'failureReason':
        'Âm thanh quá nhỏ để nhận dạng giọng nói. Thử lại hoặc thêm phụ đề cho video.',
  },
];

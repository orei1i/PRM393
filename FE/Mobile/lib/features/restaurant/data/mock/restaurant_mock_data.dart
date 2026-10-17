// lib/features/restaurant/data/mock/restaurant_mock_data.dart
//
// Same restaurants, ids, coordinates, certification, media and reviews as
// the web admin mock (FE/Web/src/lib/mock_restaurants.ts), so the nearby
// list, its map, search and the sponsored "Được tài trợ" row agree. Fictional names only: we never
// imply a real place's certification. Review comments mention dishes (bún
// riêu, phở chay, cơm tấm chay, lẩu nấm, bánh xèo, sữa hạt) so dish search
// and suggestions work.
//
// QA hook: "Quán thử nghiệm QA #fail" rejects every write (review) with 503.

/// Reviewer names by user id (`users.full_name`).
const Map<String, String> mockRestaurantPeople = {
  'u_me': 'Minh Anh',
  'u_thao_vy': 'Thảo Vy',
  'u_hoang_nam': 'Hoàng Nam',
  'u_ngoc_tram': 'Ngọc Trâm',
  'u_duc_huy': 'Đức Huy',
  'u_bep_may': 'Bếp Chay Nhà Mây',
  'u_new_1': 'Phan Gia Bảo',
  'u_new_2': 'Lý Thanh Trúc',
  'u_new_3': 'Đỗ Hải Yến',
  'u_chef_tam': 'Lê Quang Tâm',
  'u_gen_0': 'Nguyễn Thị An',
  'u_gen_1': 'Vũ Ngọc Linh',
};

typedef RestaurantSeed = ({
  String id,
  String name,
  String address,
  bool certified,
  String? createdBy,
  double? lat,
  double? lng,
});

RestaurantSeed _s(String id, String name, String address, bool certified,
        String? createdBy,
        [double? lat, double? lng]) =>
    (
      id: id,
      name: name,
      address: address,
      certified: certified,
      createdBy: createdBy,
      lat: lat,
      lng: lng,
    );

final List<RestaurantSeed> mockRestaurantSeeds = [
  _s(
      'rs_an_lac',
      'Quán Chay An Lạc',
      '12 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP.HCM',
      true,
      null,
      10.7812,
      106.699),
  _s(
      'rs_thanh_tinh',
      'Chay Thanh Tịnh',
      '5 Tôn Thất Thiệp, P. Bến Nghé, Q.1, TP.HCM',
      false,
      null,
      10.7745,
      106.7032),
  _s(
      'rs_sen_hong',
      'Bếp Chay Sen Hồng',
      '45 Trần Quốc Thảo, P. Võ Thị Sáu, Q.3, TP.HCM',
      true,
      null,
      10.785,
      106.6862),
  _s('rs_tam_nhu', 'Cơm Chay Tâm Như', '210 Lê Văn Sỹ, P.14, Q.3, TP.HCM', true,
      null, 10.7905, 106.6788),
  _s(
      'rs_nha_gao',
      'Cơm Chay Nhà Gạo',
      '73 Võ Văn Tần, P. Võ Thị Sáu, Q.3, TP.HCM',
      true,
      'u_hoang_nam',
      10.7781,
      106.6901),
  _s('rs_moc_nhien', 'Lẩu Nấm Chay Mộc Nhiên',
      '88 Nguyễn Trãi, P.3, Q.5, TP.HCM', true, null, 10.7578, 106.6815),
  _s('rs_bo_de', 'Phở Chay Bồ Đề Xanh',
      '17 Hải Thượng Lãn Ông, P.10, Q.5, TP.HCM', true, null, 10.7505, 106.66),
  _s(
      'rs_co_ba',
      'Bánh Xèo Chay Cô Ba Hiền',
      '36 Đường số 7, P. Tân Phong, Q.7, TP.HCM',
      false,
      null,
      10.7302,
      106.7065),
  _s(
      'rs_van_hoa',
      'Nhà Hàng Chay Vạn Hoa',
      '61 Nguyễn Thị Thập, P. Tân Hưng, Q.7, TP.HCM',
      true,
      null,
      10.738,
      106.716),
  _s(
      'rs_hanh_tam',
      'Bún Riêu Chay Hạnh Tâm',
      '152 Đinh Tiên Hoàng, P.1, Q. Bình Thạnh, TP.HCM',
      true,
      null,
      10.8003,
      106.6977),
  _s(
      'rs_lanh',
      'Sữa Hạt & Chay Lành',
      '24 Nguyễn Gia Trí, P.25, Q. Bình Thạnh, TP.HCM',
      true,
      null,
      10.8036,
      106.7155),
  // Member submissions from the app: uncertified, no coordinates.
  _s('rs_ut_muoi', 'Cơm Tấm Chay Út Mười',
      'Hẻm 120 Bùi Viện, P. Phạm Ngũ Lão, Q.1, TP.HCM', false, 'u_me'),
  _s('rs_nha_la', 'Quán Chay Nhà Lá',
      'Gian 12, chợ Bà Chiểu, Q. Bình Thạnh, TP.HCM', false, 'u_thao_vy'),
  _s('rs_qa_fail', 'Quán thử nghiệm QA #fail',
      '1 Đường thử nghiệm, Q.5, TP.HCM', false, 'u_new_1'),
];

typedef MediaSeed = (
  String restaurantId,
  String mediaType,
  String file,
  String? uploadedBy,
  int daysAgo
);

/// `restaurant_media`, same order and files as the web mock (`rm_<n>` ids,
/// `MEDIA_SEEDS` in FE/Web `src/lib/mock_restaurants.ts`). `null` uploader
/// = the admin team. URLs are illustrative: the app draws an illustrated
/// cover under each photo, so a missing file never shows as broken.
const List<MediaSeed> mockRestaurantMediaSeeds = [
  ('rs_an_lac', 'Image', 'an_lac_mat_tien.jpg', null, 40),
  ('rs_an_lac', 'Image', 'an_lac_bun_rieu.jpg', 'u_me', 3),
  ('rs_hanh_tam', 'Image', 'hanh_tam_to_bun.jpg', null, 30),
  ('rs_hanh_tam', 'Video', 'hanh_tam_gioi_thieu.mp4', null, 30),
  ('rs_moc_nhien', 'Image', 'moc_nhien_lau_nam.jpg', 'u_chef_tam', 12),
  ('rs_nha_gao', 'Image', 'nha_gao_com_gao_lut.jpg', 'u_hoang_nam', 17),
  ('rs_nha_gao', 'Image', 'nha_gao_quay.jpg', 'u_hoang_nam', 17),
  ('rs_ut_muoi', 'Image', 'ut_muoi_com_tam.jpg', 'u_me', 1),
  ('rs_ut_muoi', 'Image', 'ut_muoi_mat_tien.jpg', 'u_me', 1),
  ('rs_ut_muoi', 'Video', 'ut_muoi_quay_quan.mp4', 'u_me', 1),
  ('rs_nha_la', 'Image', 'nha_la_gian_hang.jpg', 'u_thao_vy', 4),
];

const mockMediaBase = 'https://res.cloudinary.com/veganlife';

typedef ReviewSeed = (
  String userId,
  int rating,
  String comment,
  double daysAgo
);

/// Review ids are `rv_<restaurant id without rs_>_<n>`, like the web mock.
const Map<String, List<ReviewSeed>> mockReviewSeeds = {
  'rs_an_lac': [
    (
      'u_me',
      5,
      'Bún riêu chay đậm vị, riêu đậu hũ mềm, nước dùng ngọt từ rau củ. Sẽ quay lại!',
      3
    ),
    (
      'u_hoang_nam',
      4,
      'Phở chay nước trong, nhiều nấm. Trưa đông nên chờ hơi lâu.',
      9
    ),
    (
      'u_ngoc_tram',
      5,
      'Quán sạch, nhân viên dễ thương, thực đơn ghi rõ món thuần chay không trứng sữa.',
      16
    ),
    (
      'u_duc_huy',
      4,
      'Cơm tấm chay sườn non làm từ đậu khá giống thật, giá hợp lý.',
      30
    ),
  ],
  'rs_thanh_tinh': [
    (
      'u_hoang_nam',
      4,
      'Cơm chay văn phòng nhanh gọn, có giao hàng trong Q.1.',
      4
    ),
    (
      'u_thao_vy',
      2,
      'Vỏ chả giò chay có vẻ dùng trứng, cần quán xác nhận lại nguyên liệu.',
      12
    ),
    ('u_gen_1', 4, 'Mì xào chay giòn, rau cải ngọt.', 20),
  ],
  'rs_sen_hong': [
    (
      'u_thao_vy',
      5,
      'Lẩu nấm thập cẩm cho 2 người rất đầy đặn, nước lẩu thanh.',
      2
    ),
    ('u_new_2', 4, 'Gỏi cuốn chay tươi, nước chấm tương đậu phộng ngon.', 11),
    (
      'u_bep_may',
      5,
      'Không gian yên tĩnh, hợp đi cùng gia đình. Bánh xèo chay giòn rụm.',
      20
    ),
  ],
  'rs_tam_nhu': [
    (
      'u_duc_huy',
      4,
      'Cơm phần chay nhiều rau, 45k no bụng. Canh rong biển ngon.',
      1
    ),
    ('u_gen_0', 4, 'Cơm tấm chay bì chả đầy đủ, chả làm từ đậu hũ non.', 7),
    ('u_gen_1', 3, 'Đồ ăn ổn nhưng hơi mặn, giờ trưa khá đông.', 14),
    (
      'u_new_3',
      5,
      'Có món riêng cho bé ăn dặm chay, chủ quán tư vấn nhiệt tình.',
      25
    ),
  ],
  'rs_nha_gao': [
    ('u_me', 5, 'Cơm gạo lứt muối mè và canh nấm, hợp người đang ăn kiêng.', 6),
    ('u_new_3', 4, 'Quán nhỏ xinh, nêm vừa, có sữa hạt tự làm.', 17),
    ('u_duc_huy', 4, 'Cơm tấm chay khá ổn, giá sinh viên.', 29),
  ],
  'rs_moc_nhien': [
    (
      'u_me',
      5,
      'Lẩu nấm 7 loại, nấm tươi, nước dùng ngọt thanh không bột ngọt.',
      5
    ),
    (
      'u_chef_tam',
      5,
      'Nấm sơ chế kỹ, rau ăn kèm sạch. Hợp nhóm bạn đi đông.',
      12
    ),
    ('u_hoang_nam', 4, 'Lẩu nấm ngon nhưng giá hơi cao so với khu vực.', 18),
    ('u_new_1', 4, 'Đậu hũ phô mai chay thả lẩu rất béo, nên thử.', 40),
    ('u_thao_vy', 5, 'Phục vụ nhanh, có phòng riêng cho gia đình.', 55),
  ],
  'rs_bo_de': [
    (
      'u_ngoc_tram',
      5,
      'Phở chay nước dùng ninh từ củ cải, bắp và nấm hương, đúng vị phở Bắc.',
      4
    ),
    ('u_gen_0', 4, 'Bánh cuốn chay nhân nấm mèo mỏng, mềm.', 10),
    ('u_duc_huy', 4, 'Sáng chủ nhật đông, nên đến trước 8 giờ.', 22),
  ],
  'rs_co_ba': [
    (
      'u_new_2',
      4,
      'Bánh xèo chay giòn, nhân củ sắn nấm mèo, rau rừng ăn kèm nhiều.',
      6
    ),
    (
      'u_thao_vy',
      3,
      'Bánh xèo ngon nhưng chưa rõ nước chấm có dùng nước mắm thật không.',
      13
    ),
    ('u_bep_may', 4, 'Bánh khọt chay cũng đáng thử.', 27),
  ],
  'rs_van_hoa': [
    ('u_bep_may', 4, 'Thực đơn tiệc chay đa dạng, hợp đặt bàn giỗ chạp.', 7),
    (
      'u_gen_0',
      5,
      'Lẩu nấm và gỏi ngó sen chay rất ngon, phục vụ chuyên nghiệp.',
      19
    ),
    ('u_duc_huy', 3, 'Món ngon nhưng cuối tuần phải chờ lâu.', 31),
    ('u_new_1', 4, 'Có chỗ đậu ô tô, tiện đi cả gia đình.', 46),
  ],
  'rs_hanh_tam': [
    (
      'u_me',
      5,
      'Bún riêu chay ngon nhất mình từng ăn: riêu đậu hũ, cà chua chín, mắm tôm chay để riêng.',
      2
    ),
    (
      'u_new_3',
      5,
      'Quán nhỏ nhưng sạch, có bún riêu chay ít cay cho trẻ em.',
      8
    ),
    ('u_hoang_nam', 4, 'Bún mọc chay cũng ngon, chỗ để xe hơi chật.', 15),
    ('u_gen_1', 5, 'Giá rẻ, 35k một tô đầy đặn.', 33),
  ],
  'rs_lanh': [
    ('u_new_2', 5, 'Sữa hạt óc chó ít ngọt, có bán theo chai mang về.', 3),
    ('u_ngoc_tram', 4, 'Bánh mì chay pate nấm ngon, sữa hạt sen thơm.', 9),
    (
      'u_chef_tam',
      4,
      'Nguyên liệu hạt rõ nguồn gốc. Nên thêm lựa chọn không đường.',
      21
    ),
  ],
  'rs_ut_muoi': [
    (
      'u_thao_vy',
      4,
      'Cơm tấm chay sườn nướng sả thơm, quán vỉa hè nhưng sạch sẽ.',
      1
    ),
  ],
  'rs_qa_fail': [
    (
      'u_new_1',
      3,
      'Đánh giá thử nghiệm QA #fail — xoá sẽ báo lỗi để kiểm tra hoàn tác.',
      0.5
    ),
  ],
};

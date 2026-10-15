// lib/features/chef/data/mock/chef_mock_data.dart

Map<String, dynamic> _pkg(String id, String name, String desc, int minutes,
        int price, String mode) =>
    {
      'id': id,
      'name': name,
      'description': desc,
      'durationMinutes': minutes,
      'priceVnd': price,
      'mode': mode,
    };

final List<Map<String, dynamic>> seedChefs = [
  {
    'id': 'u_chef_tam',
    'fullName': 'Lê Quang Tâm',
    'headline': 'Bếp trưởng nhà hàng chay · 15 năm đứng bếp',
    'specialties': ['Ẩm thực chay Việt', 'Meal prep'],
    'rating': 4.9,
    'reviewCount': 212,
    'yearsExperience': 15,
    'city': 'TP. Hồ Chí Minh',
    'startingPriceVnd': 350000,
    'consultCount': 640,
    'bio': 'Từng làm bếp trưởng tại hai nhà hàng chay ở Quận 1. Tâm giúp gia đình chuyển sang ăn chay mà vẫn giữ '
        'được vị quen của món Việt, đồng thời lên kế hoạch nấu một lần cho cả tuần.',
    'certificates': [
      'Chứng chỉ Đầu bếp chuyên nghiệp — Trường CĐ Du lịch Sài Gòn',
      'Giấy xác nhận kiến thức an toàn thực phẩm (2025)',
    ],
    'packages': [
      _pkg(
          'pk_tam_menu',
          'Tư vấn thực đơn gia đình 7 ngày',
          'Gọi video 60 phút + file thực đơn & danh sách đi chợ.',
          60,
          350000,
          'online'),
      _pkg(
          'pk_tam_home',
          'Dạy nấu 3 món chay tại nhà',
          'Chef đến bếp nhà bạn, nguyên liệu tính riêng.',
          180,
          1200000,
          'at_home'),
    ],
  },
  {
    'id': 'u_thu_ha',
    'fullName': 'ThS. DD Phạm Thu Hà',
    'headline': 'Chuyên gia dinh dưỡng lâm sàng',
    'specialties': ['Dinh dưỡng lâm sàng', 'Giảm cân lành mạnh'],
    'rating': 4.8,
    'reviewCount': 156,
    'yearsExperience': 9,
    'city': 'Hà Nội',
    'startingPriceVnd': 450000,
    'consultCount': 410,
    'bio':
        'Tư vấn ăn chay đủ chất cho người có bệnh nền (tiểu đường, mỡ máu) và người muốn giảm cân bền vững. '
            'Mỗi buổi đều dựa trên hồ sơ sức khoẻ bạn đã nhập trong VeganLife.',
    'certificates': [
      'Thạc sĩ Dinh dưỡng — Trường ĐH Y Hà Nội',
      'Chứng chỉ hành nghề dinh dưỡng lâm sàng'
    ],
    'packages': [
      _pkg(
          'pk_ha_quick',
          'Tư vấn nhanh 30 phút',
          'Giải đáp 1–2 vấn đề cụ thể về dinh dưỡng thuần chay.',
          30,
          450000,
          'online'),
      _pkg(
          'pk_ha_plan',
          'Đánh giá dinh dưỡng & kế hoạch 4 tuần',
          'Phân tích khẩu phần, chỉ số, gợi ý xét nghiệm cần làm.',
          75,
          850000,
          'online'),
    ],
  },
  {
    'id': 'u_chef_chau',
    'fullName': 'Tôn Nữ Minh Châu',
    'headline': 'Nghệ nhân ẩm thực chay cung đình Huế',
    'specialties': ['Ẩm thực chay Huế'],
    'rating': 4.9,
    'reviewCount': 98,
    'yearsExperience': 20,
    'city': 'Huế',
    'startingPriceVnd': 500000,
    'consultCount': 220,
    'bio':
        'Gìn giữ các món chay cung đình và chay chùa Huế; nhận dạy nấu cho tiệc chay gia đình, giỗ chạp.',
    'certificates': ['Nghệ nhân ẩm thực — Hiệp hội Văn hoá Ẩm thực Việt Nam'],
    'packages': [
      _pkg(
          'pk_chau_party',
          'Lên thực đơn tiệc chay 10 món',
          'Thực đơn, định lượng cho 20–50 khách, mẹo bày biện.',
          90,
          900000,
          'online'),
      _pkg('pk_chau_class', 'Lớp nấu chay Huế 1 kèm 1',
          'Học 2 món cung đình qua video call.', 120, 500000, 'online'),
    ],
  },
  {
    'id': 'u_chef_khoa',
    'fullName': 'Nguyễn Đăng Khoa',
    'headline': 'HLV thể hình · dinh dưỡng thể thao thuần chay',
    'specialties': ['Dinh dưỡng thể thao', 'Meal prep'],
    'rating': 4.7,
    'reviewCount': 73,
    'yearsExperience': 6,
    'city': 'Đà Nẵng',
    'startingPriceVnd': 300000,
    'consultCount': 150,
    'bio':
        'Giúp người tập gym tăng cơ với đạm thực vật: tempeh, đậu lăng, seitan, đạm đậu Hà Lan.',
    'certificates': [
      'Chứng chỉ Huấn luyện viên cá nhân (ISSA)',
      'Sports Nutrition Specialist'
    ],
    'packages': [
      _pkg(
          'pk_khoa_macro',
          'Tính macro & thực đơn tăng cơ',
          'Theo cân nặng, lịch tập và ngân sách của bạn.',
          45,
          300000,
          'online'),
    ],
  },
  {
    'id': 'u_chef_lan',
    'fullName': 'Võ Thị Ngọc Lan',
    'headline': 'Bếp chay cho bé ăn dặm & mẹ bầu',
    'specialties': ['Bếp chay cho bé', 'Dinh dưỡng lâm sàng'],
    'rating': 4.8,
    'reviewCount': 64,
    'yearsExperience': 8,
    'city': 'TP. Hồ Chí Minh',
    'startingPriceVnd': 400000,
    'consultCount': 130,
    'bio':
        'Thực đơn ăn dặm thuần chay đủ sắt, kẽm, B12 cho bé từ 6 tháng; phối hợp bác sĩ nhi khi cần.',
    'certificates': ['Cử nhân Dinh dưỡng — ĐH Y Dược TP.HCM'],
    'packages': [
      _pkg('pk_lan_baby', 'Thực đơn ăn dặm 4 tuần',
          'Theo tháng tuổi, kèm cách bổ sung vi chất.', 60, 400000, 'online'),
    ],
  },
  {
    'id': 'u_chef_minh',
    'fullName': 'Trần Quốc Minh',
    'headline': 'Thực dưỡng & thực phẩm lên men',
    'specialties': ['Thực dưỡng'],
    'rating': 4.6,
    'reviewCount': 41,
    'yearsExperience': 11,
    'city': 'Đà Lạt',
    'startingPriceVnd': 280000,
    'consultCount': 95,
    'bio':
        'Hướng dẫn làm tương, miso, kim chi chay và cân bằng âm dương trong bữa ăn hằng ngày.',
    'certificates': ['Khoá Thực dưỡng chuyên sâu — Kushi Institute (online)'],
    'packages': [
      _pkg('pk_minh_ferment', 'Lên men tại nhà cho người mới',
          'Kim chi chay, dưa cải, sữa chua dừa.', 60, 280000, 'online'),
    ],
  },
];

/// Next 7 days, three slots a day, a few already taken (deterministic per chef).
List<DateTime> buildSlots(String chefId) {
  final now = DateTime.now();
  final seed = chefId.codeUnits.fold<int>(0, (a, b) => a + b);
  const times = [(9, 0), (14, 0), (19, 30)];
  return [
    for (var day = 1; day <= 7; day++)
      for (var t = 0; t < times.length; t++)
        if ((seed + day * 3 + t) % 4 != 0)
          DateTime(
              now.year, now.month, now.day + day, times[t].$1, times[t].$2),
  ];
}

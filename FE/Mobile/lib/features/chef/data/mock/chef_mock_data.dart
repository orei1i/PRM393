// lib/features/chef/data/mock/chef_mock_data.dart
//
// Chef profiles and their services. The live copy (with orders, payments and
// consultations) is `MockCommerceDb`; this file is only its seed.

Map<String, dynamic> _svc(
  String id,
  String type,
  String title,
  int price,
  String description, {
  int? minutes,
  String? contentUrl,
}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'price': price,
      'description': description,
      if (minutes != null) 'durationMinutes': minutes,
      if (contentUrl != null) 'contentUrl': contentUrl,
    };

final List<Map<String, dynamic>> seedChefs = [
  {
    'id': 'u_chef_tam',
    'userId': 'u_chef_tam',
    'fullName': 'Lê Quang Tâm',
    'headline': 'Bếp trưởng nhà hàng chay · 15 năm đứng bếp',
    'specialties': ['Ẩm thực chay Việt', 'Meal prep'],
    'rating': 4.9,
    'reviewCount': 212,
    'yearsExperience': 15,
    'city': 'TP. Hồ Chí Minh',
    'consultCount': 640,
    'bio': 'Từng làm bếp trưởng tại hai nhà hàng chay ở Quận 1. Tâm giúp gia đình chuyển sang ăn chay mà vẫn giữ '
        'được vị quen của món Việt, đồng thời lên kế hoạch nấu một lần cho cả tuần.',
    'certificates': [
      'Chứng chỉ Đầu bếp chuyên nghiệp — Trường CĐ Du lịch Sài Gòn',
      'Giấy xác nhận kiến thức an toàn thực phẩm (2025)',
    ],
    'services': [
      _svc('svc_tam_consult', 'Consult', 'Tư vấn thực đơn gia đình 7 ngày',
          350000, 'Gọi video 60 phút + file thực đơn & danh sách đi chợ.',
          minutes: 60),
      _svc('svc_tam_course', 'Course', 'Khoá meal prep chay 4 tuần', 990000,
          '12 video bài học: lên thực đơn, đi chợ một lần, nấu và bảo quản cho cả tuần.',
          contentUrl: 'https://learn.veganlife.vn/mock/meal-prep-chay-4-tuan'),
      _svc(
          'svc_tam_vip',
          'VIP Menu',
          'Thực đơn VIP 30 ngày cho gia đình',
          1500000,
          'Thực đơn 3 bữa/ngày cho 4 người, kèm danh sách đi chợ theo tuần.',
          contentUrl:
              'https://files.veganlife.vn/mock/thuc-don-vip-30-ngay-gia-dinh.pdf'),
    ],
  },
  {
    'id': 'u_thu_ha',
    'userId': 'u_thu_ha',
    'fullName': 'ThS. DD Phạm Thu Hà',
    'headline': 'Chuyên gia dinh dưỡng lâm sàng',
    'specialties': ['Dinh dưỡng lâm sàng', 'Giảm cân lành mạnh'],
    'rating': 4.8,
    'reviewCount': 156,
    'yearsExperience': 9,
    'city': 'Hà Nội',
    'consultCount': 410,
    'bio':
        'Tư vấn ăn chay đủ chất cho người có bệnh nền (tiểu đường, mỡ máu) và người muốn giảm cân bền vững. '
            'Mỗi buổi đều dựa trên hồ sơ sức khoẻ bạn đã nhập trong VeganLife.',
    'certificates': [
      'Thạc sĩ Dinh dưỡng — Trường ĐH Y Hà Nội',
      'Chứng chỉ hành nghề dinh dưỡng lâm sàng'
    ],
    'services': [
      _svc('svc_ha_quick', 'Consult', 'Tư vấn nhanh 30 phút', 450000,
          'Giải đáp 1–2 vấn đề cụ thể về dinh dưỡng thuần chay.',
          minutes: 30),
      _svc('svc_ha_plan', 'Consult', 'Đánh giá dinh dưỡng & kế hoạch 4 tuần',
          850000, 'Phân tích khẩu phần, chỉ số, gợi ý xét nghiệm cần làm.',
          minutes: 75),
      _svc(
          'svc_ha_vip',
          'VIP Menu',
          'Thực đơn VIP 30 ngày giảm cân lành mạnh',
          690000,
          'Thực đơn 1.500 kcal/ngày đủ đạm, B12 và sắt, cập nhật theo tuần.',
          contentUrl:
              'https://files.veganlife.vn/mock/thuc-don-vip-giam-can-30-ngay.pdf'),
    ],
  },
  {
    'id': 'u_chef_chau',
    'userId': 'u_chef_chau',
    'fullName': 'Tôn Nữ Minh Châu',
    'headline': 'Nghệ nhân ẩm thực chay cung đình Huế',
    'specialties': ['Ẩm thực chay Huế'],
    'rating': 4.9,
    'reviewCount': 98,
    'yearsExperience': 20,
    'city': 'Huế',
    'consultCount': 220,
    'bio':
        'Gìn giữ các món chay cung đình và chay chùa Huế; nhận dạy nấu cho tiệc chay gia đình, giỗ chạp.',
    'certificates': ['Nghệ nhân ẩm thực — Hiệp hội Văn hoá Ẩm thực Việt Nam'],
    'services': [
      _svc('svc_chau_party', 'Consult', 'Lên thực đơn tiệc chay 10 món', 900000,
          'Thực đơn, định lượng cho 20–50 khách, mẹo bày biện.',
          minutes: 90),
      _svc('svc_chau_class', 'Consult', 'Lớp nấu chay Huế 1 kèm 1', 500000,
          'Học 2 món cung đình qua video call.',
          minutes: 120),
    ],
  },
  {
    'id': 'u_chef_khoa',
    'userId': 'u_chef_khoa',
    'fullName': 'Nguyễn Đăng Khoa',
    'headline': 'HLV thể hình · dinh dưỡng thể thao thuần chay',
    'specialties': ['Dinh dưỡng thể thao', 'Meal prep'],
    'rating': 4.7,
    'reviewCount': 73,
    'yearsExperience': 6,
    'city': 'Đà Nẵng',
    'consultCount': 150,
    'bio':
        'Giúp người tập gym tăng cơ với đạm thực vật: tempeh, đậu lăng, seitan, đạm đậu Hà Lan.',
    'certificates': [
      'Chứng chỉ Huấn luyện viên cá nhân (ISSA)',
      'Sports Nutrition Specialist'
    ],
    'services': [
      _svc('svc_khoa_macro', 'Consult', 'Tính macro & thực đơn tăng cơ', 300000,
          'Theo cân nặng, lịch tập và ngân sách của bạn.',
          minutes: 45),
      _svc('svc_khoa_course', 'Course', 'Khoá tăng cơ thuần chay 8 tuần',
          790000, 'Giáo án tập + thực đơn đạm thực vật theo từng tuần.',
          contentUrl: 'https://learn.veganlife.vn/mock/tang-co-thuan-chay'),
    ],
  },
  {
    'id': 'u_chef_lan',
    'userId': 'u_chef_lan',
    'fullName': 'Võ Thị Ngọc Lan',
    'headline': 'Bếp chay cho bé ăn dặm & mẹ bầu',
    'specialties': ['Bếp chay cho bé', 'Dinh dưỡng lâm sàng'],
    'rating': 4.8,
    'reviewCount': 64,
    'yearsExperience': 8,
    'city': 'TP. Hồ Chí Minh',
    'consultCount': 130,
    'bio':
        'Thực đơn ăn dặm thuần chay đủ sắt, kẽm, B12 cho bé từ 6 tháng; phối hợp bác sĩ nhi khi cần.',
    'certificates': ['Cử nhân Dinh dưỡng — ĐH Y Dược TP.HCM'],
    'services': [
      _svc('svc_lan_baby', 'Consult', 'Thực đơn ăn dặm 4 tuần', 400000,
          'Theo tháng tuổi, kèm cách bổ sung vi chất.',
          minutes: 60),
    ],
  },
  {
    'id': 'u_chef_minh',
    'userId': 'u_chef_minh',
    'fullName': 'Trần Quốc Minh',
    'headline': 'Thực dưỡng & thực phẩm lên men',
    'specialties': ['Thực dưỡng'],
    'rating': 4.6,
    'reviewCount': 41,
    'yearsExperience': 11,
    'city': 'Đà Lạt',
    'consultCount': 95,
    'bio':
        'Hướng dẫn làm tương, miso, kim chi chay và cân bằng âm dương trong bữa ăn hằng ngày.',
    'certificates': ['Khoá Thực dưỡng chuyên sâu — Kushi Institute (online)'],
    'services': [
      _svc('svc_minh_ferment', 'Consult', 'Lên men tại nhà cho người mới',
          280000, 'Kim chi chay, dưa cải, sữa chua dừa.',
          minutes: 60),
    ],
  },
];

/// Next 7 days, three slots a day, a few already taken (deterministic per
/// chef). [now] is the mock clock.
List<DateTime> buildSlots(String chefId, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final seed = chefId.codeUnits.fold<int>(0, (a, b) => a + b);
  const times = [(9, 0), (14, 0), (19, 30)];
  return [
    for (var day = 1; day <= 7; day++)
      for (var t = 0; t < times.length; t++)
        if ((seed + day * 3 + t) % 4 != 0)
          DateTime(today.year, today.month, today.day + day, times[t].$1,
              times[t].$2),
  ];
}

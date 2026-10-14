// lib/features/chatbot/data/mock_chat_repository.dart
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/mock_delay.dart';
import 'chat_api_service.dart';
import 'models/chat_models.dart';

/// Simulated RAG backend:
/// * streams canned Vietnamese answers word by word with citations,
/// * counts guest questions per guest token (persisted, like the server would),
/// * include `#offline` in a question to simulate a dropped connection mid-stream.
class MockChatRepository implements ChatApiService {
  MockChatRepository({required this.prefs, required this.readSession});

  final SharedPreferences prefs;
  final AuthSession Function() readSession;
  final _random = Random();

  String _usedKey(String guestToken) => 'vl.mock.trial_used.$guestToken';

  @override
  Future<TrialStatusDto> getGuestTrialStatus() async {
    await mockDelay(250);
    final session = readSession();
    return TrialStatusDto(
      limit: Env.guestTrialLimit,
      used: prefs.getInt(_usedKey(session.guestToken)) ?? 0,
    );
  }

  @override
  Stream<ChatStreamEvent> streamReply({
    required String sessionId,
    required ChatRequestDto request,
    CancelToken? cancelToken,
  }) async* {
    final session = readSession();
    final usedKey = _usedKey(session.guestToken);
    final used = prefs.getInt(usedKey) ?? 0;
    // A resumed answer is the same question → not charged twice.
    if (session.isGuest && request.resumeFrom == 0 && used >= Env.guestTrialLimit) {
      await mockDelay(300);
      throw const TrialExhaustedException();
    }

    await mockDelay(450); // time to first token
    final answer = _pickAnswer(request.message);
    final simulateDrop = request.message.contains('#offline') && request.resumeFrom == 0;
    final dropAt = (answer.text.length * 0.45).round();

    // Citations referenced before the resume point were already delivered.
    final sent = <int>{};
    for (final c in answer.citations) {
      if (answer.text.indexOf('[${c.index}]') < request.resumeFrom) sent.add(c.index);
    }

    var position = request.resumeFrom.clamp(0, answer.text.length).toInt();
    final words = RegExp(r'\S+\s*').allMatches(answer.text.substring(position)).map((m) => m.group(0)!);

    for (final word in words) {
      if (cancelToken?.isCancelled ?? false) return;
      await Future<void>.delayed(Duration(milliseconds: 28 + _random.nextInt(45)));
      if (simulateDrop && position >= dropAt) {
        throw const ApiException(message: 'Mất kết nối giữa chừng.', code: 'network');
      }
      yield ChatTokenEvent(word);
      position += word.length;

      for (final c in answer.citations) {
        if (!sent.contains(c.index) && word.contains('[${c.index}]')) {
          sent.add(c.index);
          yield ChatCitationEvent(c);
        }
      }
    }

    int? remaining;
    if (session.isGuest && request.resumeFrom == 0) {
      await prefs.setInt(usedKey, used + 1);
      remaining = max(0, Env.guestTrialLimit - used - 1);
    } else if (session.isGuest) {
      remaining = max(0, Env.guestTrialLimit - used);
    }
    yield ChatDoneEvent(messageId: 'msg_${DateTime.now().millisecondsSinceEpoch}', trialRemaining: remaining);
  }

  _CannedAnswer _pickAnswer(String question) {
    final q = question.toLowerCase();
    if (q.contains('sắt') || q.contains('iron')) return _ironAnswer;
    if (q.contains('thay') || q.contains('tempeh') || q.contains('substitut')) return _tofuSwapAnswer;
    if (q.contains('đạm') || q.contains('protein') || q.contains('hoàn chỉnh')) return _proteinAnswer;
    if (q.contains('b12')) return _b12Answer;
    return _generalAnswer;
  }
}

class _CannedAnswer {
  const _CannedAnswer(this.text, this.citations);
  final String text;
  final List<CitationDto> citations;
}

// Sample passages below are Vietnamese summaries for demo purposes; in
// production `passage` is the exact chunk returned by the retriever.

const _nihIron = CitationDto(
  index: 2,
  title: 'Iron – Fact Sheet for Health Professionals',
  publisher: 'NIH Office of Dietary Supplements',
  sourceType: 'scientific',
  url: 'https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/',
  passage: 'Nhu cầu sắt khuyến nghị cho người ăn chay cao gấp khoảng 1,8 lần người ăn thịt, '
      'vì sắt non-heme từ thực vật được hấp thu kém hơn sắt heme. Vitamin C giúp tăng hấp thu sắt non-heme.',
  verified: true,
);

const _ironAnswer = _CannedAnswer(
  'Thực đơn tuần này của bạn trung bình cung cấp **12,6 mg sắt/ngày**, thấp hơn mục tiêu **18 mg** [1].\n\n'
  'Sắt từ thực vật (sắt non-heme) được hấp thu kém hơn sắt từ thịt, nên khuyến nghị cho người ăn chay '
  'cao hơn khoảng **1,8 lần** [2].\n\n'
  '**Ba cách cải thiện ngay trong thực đơn:**\n\n'
  '1. Thêm 1 chén đậu lăng nấu chín vào bữa trưa thứ Năm (khoảng +6,6 mg).\n'
  '2. Ăn kèm nguồn vitamin C như ớt chuông, chanh, ổi trong bữa có đậu hũ [2].\n'
  '3. Uống trà, cà phê cách bữa ăn ít nhất 1 giờ [3].',
  [
    CitationDto(
      index: 1,
      title: 'Thực đơn tuần của bạn',
      publisher: 'VeganLife · dữ liệu cá nhân',
      sourceType: 'user_data',
      passage: 'Tổng sắt 7 ngày: 88,2 mg · trung bình 12,6 mg/ngày · mục tiêu hồ sơ: 18 mg/ngày.',
    ),
    _nihIron,
    CitationDto(
      index: 3,
      title: 'Bếp chay giàu sắt',
      publisher: 'Chef Mai Anh · đầu bếp đã xác minh',
      sourceType: 'chef_document',
      passage: 'Tannin trong trà và cà phê làm giảm hấp thu sắt non-heme; nên dùng cách xa bữa ăn chính.',
      verified: true,
    ),
  ],
);

const _tofuSwapAnswer = _CannedAnswer(
  'Bạn có thể thay đậu hũ bằng **tempeh** theo tỉ lệ 1:1. Tempeh chắc hơn, giữ hình tốt khi xào '
  'và thường nhiều đạm hơn đậu hũ trên cùng 100 g [1].\n\n'
  'Nếu bạn cần tránh đậu nành, hãy dùng **đậu gà** hoặc **nấm đùi gà xé** cho món xào, '
  '**đậu lăng** cho món hầm [2].\n\n'
  'Mẹo: hấp tempeh khoảng 10 phút trước khi chế biến để bớt vị đắng.',
  [
    CitationDto(
      index: 1,
      title: 'FoodData Central: Tempeh; Tofu, firm',
      publisher: 'USDA',
      sourceType: 'scientific',
      url: 'https://fdc.nal.usda.gov/',
      passage: 'Tempeh: khoảng 19–20 g đạm/100 g. Đậu hũ cứng: khoảng 8–17 g đạm/100 g tuỳ loại.',
      verified: true,
    ),
    CitationDto(
      index: 2,
      title: 'Thay thế đạm thực vật trong bếp Việt',
      publisher: 'Chef Mai Anh · đầu bếp đã xác minh',
      sourceType: 'chef_document',
      passage: 'Nấm đùi gà xé và đậu gà là lựa chọn không chứa đậu nành cho món xào và món kho.',
      verified: true,
    ),
  ],
);

const _proteinAnswer = _CannedAnswer(
  'Có. Đạm đậu nành chứa đủ **9 axit amin thiết yếu**, nên đậu hũ, tempeh và sữa đậu nành '
  'được xem là nguồn đạm hoàn chỉnh [1].\n\n'
  'Với các loại đậu khác và ngũ cốc, bạn chỉ cần ăn đa dạng trong ngày là đủ, '
  'không cần kết hợp trong cùng một bữa [1].',
  [
    CitationDto(
      index: 1,
      title: 'Protein in plant-based diets',
      publisher: 'Harvard T.H. Chan School of Public Health',
      sourceType: 'scientific',
      url: 'https://nutritionsource.hsph.harvard.edu/what-should-you-eat/protein/',
      passage: 'Đậu nành cung cấp đủ các axit amin thiết yếu; chế độ ăn thực vật đa dạng trong ngày đáp ứng nhu cầu đạm.',
      verified: true,
    ),
  ],
);

const _b12Answer = _CannedAnswer(
  'Vitamin B12 gần như không có trong thực phẩm thực vật, nên người ăn thuần chay cần '
  '**thực phẩm tăng cường B12** hoặc **viên bổ sung** [1].\n\n'
  'Hãy hỏi bác sĩ về liều phù hợp và xét nghiệm định kỳ nếu bạn ăn thuần chay lâu dài.',
  [
    CitationDto(
      index: 1,
      title: 'Vitamin B12 – Fact Sheet for Consumers',
      publisher: 'NIH Office of Dietary Supplements',
      sourceType: 'scientific',
      url: 'https://ods.od.nih.gov/factsheets/VitaminB12-Consumer/',
      passage: 'B12 có tự nhiên trong thực phẩm động vật; người ăn thuần chay nên dùng thực phẩm tăng cường hoặc thực phẩm bổ sung.',
      verified: true,
    ),
  ],
);

const _generalAnswer = _CannedAnswer(
  'Một chế độ ăn thuần chay cân bằng nên có rau củ, trái cây, ngũ cốc nguyên hạt, các loại đậu '
  'và hạt mỗi ngày [1].\n\n'
  'Ba vi chất cần để ý nhất: **vitamin B12**, **sắt** và **canxi**. Bạn muốn mình xem thực đơn tuần này '
  'của bạn đang thiếu chất nào không?',
  [
    CitationDto(
      index: 1,
      title: 'Healthy diet – Fact sheet',
      publisher: 'World Health Organization',
      sourceType: 'scientific',
      url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
      passage: 'Chế độ ăn lành mạnh gồm trái cây, rau, các loại đậu, hạt và ngũ cốc nguyên hạt.',
      verified: true,
    ),
  ],
);

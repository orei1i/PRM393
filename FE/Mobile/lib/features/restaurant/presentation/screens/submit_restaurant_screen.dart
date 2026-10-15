// lib/features/restaurant/presentation/screens/submit_restaurant_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/location_service.dart';
import '../../data/models/restaurant_model.dart';
import '../../data/restaurant_api_service.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';
import 'restaurant_detail_screen.dart';

/// "Gợi ý quán mới" (members only; callers gate it with `ensureSignedIn`).
/// The place is listed right away as "Chưa chứng nhận" with "Được gợi ý bởi
/// «tên»"; on success this screen is replaced by the new restaurant's detail
/// and completes with the created [Restaurant].
class SubmitRestaurantScreen extends ConsumerStatefulWidget {
  const SubmitRestaurantScreen({super.key});

  static Route<Restaurant> route() => MaterialPageRoute<Restaurant>(
        fullscreenDialog: true,
        builder: (_) => const SubmitRestaurantScreen(),
      );

  @override
  ConsumerState<SubmitRestaurantScreen> createState() =>
      _SubmitRestaurantScreenState();
}

class _SubmitRestaurantScreenState
    extends ConsumerState<SubmitRestaurantScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _useLocation = false;
  bool _submitting = false;
  bool _attempted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      // From now on, messages update while typing.
      setState(() => _attempted = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final point = _useLocation
          ? (await ref.read(userLocationProvider.future)).point
          : null;
      final created = (await ref.read(restaurantApiProvider).createRestaurant(
                CreateRestaurantRequestDto(
                  name: _name.text.trim(),
                  address: _address.text.trim(),
                  latitude: point?.latitude,
                  longitude: point?.longitude,
                ),
              ))
          .toEntity();
      if (!mounted) return;
      ref.invalidate(restaurantListProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Đã gợi ý «${created.name}». Quán hiển thị ngay với nhãn Chưa chứng nhận.'),
      ));
      Navigator.of(context).pushReplacement(
        RestaurantDetailScreen.route(created.id, name: created.name),
        result: created,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(userLocationProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Đóng',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('Gợi ý quán mới'),
      ),
      body: Form(
        key: _form,
        autovalidateMode: _attempted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            TextFormField(
              controller: _name,
              enabled: !_submitting,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tên quán',
                hintText: 'VD: Cơm chay Hoa Sen',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v?.trim().length ?? 0) < 3
                  ? 'Tên quán cần ít nhất 3 ký tự'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _address,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 3,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ',
                hintText: 'Số nhà, đường, phường, quận, thành phố',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v?.trim().length ?? 0) < 10
                  ? 'Địa chỉ cần ít nhất 10 ký tự'
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _useLocation,
              onChanged:
                  _submitting ? null : (v) => setState(() => _useLocation = v),
              title: const Text('Dùng vị trí hiện tại cho toạ độ'),
              subtitle: Text(_useLocation && location != null
                  ? location.label
                  : 'Bật khi bạn đang ở quán, để mọi người thấy khoảng cách và chỉ đường.'),
            ),
            const SizedBox(height: 8),
            VLCard(
              color: context.colors.secondaryContainer,
              borderColor: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: context.colors.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quán mới hiển thị ngay với nhãn Chưa chứng nhận. '
                      'Ban quản trị sẽ xác minh trước khi gắn nhãn Chứng nhận chay.',
                      style: context.textStyles.bodyMedium?.copyWith(
                          color: context.colors.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 20, color: context.colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.colors.error)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Gửi gợi ý'),
            ),
            const SizedBox(height: 8),
            Text(
              'Thông tin sai hoặc trùng sẽ bị Ban quản trị gỡ.',
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
          ],
        ),
      ),
    );
  }
}

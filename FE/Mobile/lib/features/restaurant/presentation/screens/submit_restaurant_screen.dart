// lib/features/restaurant/presentation/screens/submit_restaurant_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/data/media_api_service.dart';
import '../../../community/data/media_picker.dart';
import '../../data/location_service.dart';
import '../../data/models/restaurant_model.dart';
import '../../data/restaurant_api_service.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';
import '../controllers/restaurant_controllers.dart';
import '../widgets/vl_map.dart';
import 'location_picker_screen.dart';
import 'restaurant_detail_screen.dart';

/// "Gợi ý quán mới" (members only; callers gate it with `ensureSignedIn`).
/// The place's position comes from "Chọn trên bản đồ", "Tìm địa chỉ" or
/// "Dùng vị trí hiện tại" (each also fills the address, which stays
/// editable); up to 5 photos and 1 video are uploaded first. The place is
/// listed right away as "Chưa chứng nhận" with "Được gợi ý bởi «tên»"; on
/// success this screen is replaced by the new restaurant's detail and
/// completes with the created [Restaurant].
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

/// One picked photo or video and its upload.
class _Attachment {
  _Attachment(this.file);

  final PickedMedia file;
  CancelToken token = CancelToken();
  double progress = 0;
  String? url;
  String? error;

  bool get uploading => url == null && error == null;
  RestaurantMediaType get type =>
      file.isVideo ? RestaurantMediaType.video : RestaurantMediaType.image;
}

class _SubmitRestaurantScreenState
    extends ConsumerState<SubmitRestaurantScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _media = <_Attachment>[];

  /// The restaurant's position (`null` = none yet) and how it was chosen.
  UserLocation? _place;

  /// The address text the last location filled in; replaced by the next one
  /// unless the user edited it.
  String? _autoAddress;
  bool _locating = false;
  bool _submitting = false;
  bool _attempted = false;
  String? _error;

  int get _images => _media.where((m) => !m.file.isVideo).length;
  int get _videos => _media.where((m) => m.file.isVideo).length;
  bool get _uploading => _media.any((m) => m.uploading);

  @override
  void dispose() {
    for (final m in _media) {
      if (m.uploading) m.token.cancel();
    }
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _usePlace(UserLocation place) {
    setState(() {
      _place = place;
      final text = place.address ?? place.label;
      final current = _address.text.trim();
      if (current.isEmpty || current == _autoAddress) {
        _address.text = text;
        _autoAddress = text;
      }
    });
  }

  Future<void> _pick({required bool onMap}) async {
    final start = _place ?? ref.read(userLocationProvider).valueOrNull;
    final picked = await Navigator.of(context).push(LocationPickerScreen.route(
      initial: start,
      startOnMap: onMap,
      title: 'Vị trí quán',
    ));
    if (picked != null && mounted) _usePlace(picked);
  }

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final here = await ref.read(locationServiceProvider).currentLocation();
      if (mounted) _usePlace(here);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addMedia() async {
    final kinds = {
      if (_images < CreateRestaurantRequestDto.maxImages) MediaKind.image,
      if (_videos < CreateRestaurantRequestDto.maxVideos) MediaKind.video,
    };
    if (kinds.isEmpty) return;
    final file =
        await ref.read(mediaPickerProvider).pick(context, kinds: kinds);
    if (file == null || !mounted) return;
    final invalid = MediaUploadRules.validate(file);
    if (invalid != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$invalid. Chọn tệp khác nhé.')));
      return;
    }
    // The picker may still return a kind that is full (the real gallery).
    if ((file.isVideo && _videos >= CreateRestaurantRequestDto.maxVideos) ||
        (!file.isVideo && _images >= CreateRestaurantRequestDto.maxImages)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tối đa 5 ảnh và 1 video cho mỗi gợi ý.')));
      return;
    }
    final item = _Attachment(file);
    setState(() => _media.add(item));
    _upload(item);
  }

  Future<void> _upload(_Attachment item) async {
    final api = ref.read(mediaApiProvider);
    void progress(double p) {
      if (mounted) setState(() => item.progress = p);
    }

    try {
      final url = item.file.isVideo
          ? (await api.uploadVideo(item.file,
                  onProgress: progress, cancelToken: item.token))
              .mediaUrl
          : (await api.uploadImage(item.file,
                  onProgress: progress, cancelToken: item.token))
              .mediaUrl;
      if (mounted) setState(() => item.url = url);
    } catch (e) {
      if (!mounted || !_media.contains(item)) return;
      setState(() => item.error = describeError(e));
    }
  }

  void _retry(_Attachment item) {
    setState(() {
      item
        ..error = null
        ..progress = 0
        ..token = CancelToken();
    });
    _upload(item);
  }

  void _remove(_Attachment item) {
    if (item.uploading) item.token.cancel();
    setState(() => _media.remove(item));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      // From now on, messages update while typing.
      setState(() => _attempted = true);
      return;
    }
    if (_media.any((m) => m.error != null)) {
      setState(() => _error =
          'Có tệp chưa tải lên được. Thử lại hoặc bỏ tệp đó trước khi gửi.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final point = _place?.point;
      final created = (await ref.read(restaurantApiProvider).createRestaurant(
                CreateRestaurantRequestDto(
                  name: _name.text.trim(),
                  address: _address.text.trim(),
                  latitude: point?.latitude,
                  longitude: point?.longitude,
                  media: [
                    for (final m in _media)
                      NewRestaurantMediaDto(
                          mediaType: m.type, mediaUrl: m.url!),
                  ],
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
    final busy = _submitting || _uploading;
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
            _LocationCard(
              place: _place,
              locating: _locating,
              enabled: !_submitting,
              onMap: () => _pick(onMap: true),
              onSearch: () => _pick(onMap: false),
              onCurrent: _useCurrent,
              onClear: () => setState(() => _place = null),
            ),
            const SizedBox(height: 12),
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
                helperText:
                    'Chọn vị trí ở trên để điền sẵn, rồi sửa cho đúng số nhà.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v?.trim().length ?? 0) < 10
                  ? 'Địa chỉ cần ít nhất 10 ký tự'
                  : null,
            ),
            const SizedBox(height: 12),
            _MediaSection(
              media: _media,
              canAdd: !_submitting &&
                  (_images < CreateRestaurantRequestDto.maxImages ||
                      _videos < CreateRestaurantRequestDto.maxVideos),
              onAdd: _addMedia,
              onRetry: _retry,
              onRemove: _submitting ? null : _remove,
            ),
            const SizedBox(height: 16),
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
              onPressed: busy ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_uploading ? 'Đang tải ảnh/video lên…' : 'Gửi gợi ý'),
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

/// "Vị trí quán": mini map (or the no-position warning) and the three ways
/// to set it.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.place,
    required this.locating,
    required this.enabled,
    required this.onMap,
    required this.onSearch,
    required this.onCurrent,
    required this.onClear,
  });

  final UserLocation? place;
  final bool locating;
  final bool enabled;
  final VoidCallback onMap;
  final VoidCallback onSearch;
  final VoidCallback onCurrent;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = place;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Vị trí quán', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          if (p == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.vl.cautionContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_off_outlined,
                      size: 20, color: context.vl.onCautionContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chưa có vị trí trên bản đồ — mọi người sẽ không thấy khoảng cách và chỉ đường',
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.vl.onCautionContainer),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 140,
                child: VLMap(
                  key: ValueKey(p.point),
                  center: p.point,
                  zoom: 16,
                  interactive: false,
                  onTap: enabled ? onMap : null,
                  layers: [
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: p.point.latLng,
                          width: RestaurantPin.size,
                          height: RestaurantPin.size,
                          child: const RestaurantPin(
                              certified: false, selected: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.place_rounded,
                    size: 18, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${p.label} · ${formatCoordinates(p.point)}',
                    style: context.textStyles.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: enabled ? onClear : null,
                  child: const Text('Bỏ vị trí'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? onMap : null,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Chọn trên bản đồ'),
              ),
              OutlinedButton.icon(
                onPressed: enabled ? onSearch : null,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Tìm địa chỉ'),
              ),
              OutlinedButton.icon(
                onPressed: enabled && !locating ? onCurrent : null,
                icon: locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: const Text('Dùng vị trí hiện tại'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Ảnh & video giới thiệu (không bắt buộc)": tiles with upload progress,
/// retry and remove, plus "Thêm ảnh/video" while there is room.
class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.media,
    required this.canAdd,
    required this.onAdd,
    required this.onRetry,
    required this.onRemove,
  });

  final List<_Attachment> media;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<_Attachment> onRetry;
  final ValueChanged<_Attachment>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ảnh & video giới thiệu (không bắt buộc)',
            style: context.textStyles.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Tối đa 5 ảnh và 1 video · ${MediaUploadRules.hint}',
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in media)
              _AttachmentTile(
                item: m,
                onRetry: () => onRetry(m),
                onRemove: onRemove == null ? null : () => onRemove!(m),
              ),
            if (canAdd)
              SizedBox.square(
                dimension: 96,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onAdd,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined),
                      SizedBox(height: 4),
                      Text('Thêm ảnh/video',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.item,
    required this.onRetry,
    required this.onRemove,
  });

  final _Attachment item;
  final VoidCallback onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final f = item.file;
    return Semantics(
      label: '${f.isVideo ? 'Video' : 'Ảnh'} ${f.name}',
      child: SizedBox.square(
        dimension: 96,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FoodCover(
              seed: f.name,
              height: 96,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Icon(
                    f.isVideo ? Icons.movie_outlined : Icons.image_outlined,
                    color: Colors.white,
                    size: 28),
              ),
            ),
            if (item.uploading)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('${(item.progress * 100).round()} %',
                      style: context.textStyles.labelLarge
                          ?.copyWith(color: Colors.white)),
                ),
              ),
            if (item.error != null)
              Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onRetry,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.white),
                        Text('Thử lại', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            if (item.url != null)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
              ),
            if (onRemove != null)
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Bỏ ${f.name}',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

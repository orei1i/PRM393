// lib/core/utils/media_url.dart
import '../config/env.dart';

/// The URL to display or play a media file from.
///
/// The BE returns uploads as host-relative paths (`/uploads/images/x.png`).
/// Only for display: POST `/posts` must keep sending the raw value, because the
/// BE matches it against its media assets (an absolute URL gets a 400).
///
/// Null or empty gives null. Anything that is not host-relative is returned
/// unchanged.
String? absoluteMediaUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return raw.startsWith('/') ? '${Env.apiOrigin}$raw' : raw;
}

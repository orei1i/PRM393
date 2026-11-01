// lib/core/utils/open_url.dart
import 'package:url_launcher/url_launcher.dart';

/// Opens a link from the server in another app. `false` when it can't: a link
/// that doesn't parse, or nothing on the phone that handles it.
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}

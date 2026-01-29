import 'package:url_launcher/url_launcher.dart';

class LinkUtils {
  static Future<bool> open(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

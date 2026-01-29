// lib/features/about/view/about_screen.dart
import 'package:flutter/material.dart';
import 'package:herbalwisdom/features/about/model/about_us_model.dart';
import 'package:herbalwisdom/features/about/repo/about_repo.dart';
import 'package:herbalwisdom/common/widgets/error_view.dart';
import 'package:shimmer/shimmer.dart';
import '../../../common/utils/link_utils.dart';

class AboutScreen extends StatefulWidget {
  static const routePath = '/about';
  static const routeName = 'about';
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final AboutRepo _repo;
  Future<AboutUsDetails>? _future;

  @override
  void initState() {
    super.initState();
    _repo = AboutRepo();
    _future = _repo.getAboutUs();
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<AboutUsDetails>(
        future: _future,
        builder: (context, snap) {
          // ✅ Show shimmer while loading
          if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
            return _ShimmerAboutPlaceholder();
          }

          // ⚠️ Error view
          if (snap.hasError) {
            return ErrorView(title: 'Unable to load information', message: 'Please check your internet connection and try again.', onRetry: () => setState(() => _future = _repo.getAboutUs()));
          }

          // ✅ Loaded content
          final d = snap.data!;
          return AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 300),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(d.title ?? 'Herbal Wisdom', style: ts.headlineSmall),
                const SizedBox(height: 8),
                if (d.description != null) Text(d.description!, style: ts.bodyMedium),
                const SizedBox(height: 20),

                // 🌐 Social Links
                if (d.facebook != null || d.instagram != null || d.xOrTwitter != null || d.reddit != null || d.threads != null) ...[
                  if (d.facebook != null) _tile(icon: Icons.facebook_outlined, title: 'Facebook', subtitle: d.facebook!, onTap: () => LinkUtils.open(d.facebook!)),
                  if (d.instagram != null) _tile(icon: Icons.photo_camera_outlined, title: 'Instagram', subtitle: d.instagram!, onTap: () => LinkUtils.open(d.instagram!)),
                  if (d.xOrTwitter != null) _tile(icon: Icons.alternate_email, title: 'X / Twitter', subtitle: d.xOrTwitter!, onTap: () => LinkUtils.open(d.xOrTwitter!)),
                  if (d.reddit != null) _tile(icon: Icons.reddit, title: 'Reddit', subtitle: d.reddit!, onTap: () => LinkUtils.open(d.reddit!)),
                  if (d.threads != null) _tile(icon: Icons.tag, title: 'Threads', subtitle: d.threads!, onTap: () => LinkUtils.open(d.threads!)),
                  const Divider(height: 32),
                ],

                // 📍 Contact
                if (d.address != null) _tile(icon: Icons.location_on_outlined, title: d.address!, onTap: () => LinkUtils.open('https://maps.apple.com/?q=${Uri.encodeComponent(d.address!)}')),
                if (d.email != null) _tile(icon: Icons.email_outlined, title: d.email!, onTap: () => LinkUtils.open('mailto:${d.email!}')),
                for (final p in d.phones) _tile(icon: Icons.phone_outlined, title: p, onTap: () => LinkUtils.open('tel:$p')),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile({required IconData icon, required String title, String? subtitle, VoidCallback? onTap}) {
    return ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle != null ? Text(subtitle) : null, onTap: onTap, contentPadding: EdgeInsets.zero);
  }
}

/// 🩵 Shimmer placeholder for About Us loading
class _ShimmerAboutPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(height: 24, width: 180, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Container(height: 12, width: double.infinity, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 12, width: double.infinity, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 12, width: double.infinity, color: Colors.grey.shade300),
          const SizedBox(height: 24),
          for (int i = 0; i < 4; i++) ...[
            Row(
              children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Container(height: 14, width: 160, color: Colors.grey.shade300), const SizedBox(height: 6), Container(height: 12, width: 120, color: Colors.grey.shade300)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

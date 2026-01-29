import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:html/parser.dart' as html_parser;

import '../repo/news_repo.dart';
import '../models/news_item.dart';
import '../../../common/widgets/error_view.dart';

class NewsScreen extends StatefulWidget {
  static const routePath = '/news';
  static const routeName = 'news';
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _repo = NewsRepo();
  late Future<List<NewsItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetch();
  }

  /// 🧹 Clean HTML to display short plain summary
  String _extractPlainText(String html) {
    try {
      final doc = html_parser.parse(html);
      return doc.body?.text.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    } catch (_) {
      return html;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: FutureBuilder<List<NewsItem>>(
        future: _future,
        builder: (_, s) {
          // 🟡 Shimmer while loading
          if (s.connectionState == ConnectionState.waiting || !s.hasData) {
            return ListView.separated(padding: const EdgeInsets.all(16), itemCount: 4, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (_, __) => const _ShimmerNewsCard());
          }

          if (s.hasError) {
            return ErrorView(title: 'Unable to load news', message: 'Please check your internet connection and try again.', onRetry: () => setState(() => _future = _repo.fetch()));
          }

          final items = s.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _repo.fetch()),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) {
                final n = items[i];
                final previewText = _extractPlainText(n.summary); // ✅ Cleaned HTML
                return InkWell(
                  onTap: () => context.push('${NewsScreen.routePath}/${n.id}'),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(n.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300, child: const Icon(Icons.broken_image, size: 60))),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title, style: ts.titleMedium),
                              const SizedBox(height: 6),
                              Text(previewText, maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 8),
                              Text('${n.ts.day}/${n.ts.month}/${n.ts.year}', style: ts.bodySmall?.copyWith(color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 🔷 Shimmer placeholder card
class _ShimmerNewsCard extends StatelessWidget {
  const _ShimmerNewsCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(height: 180, color: Colors.grey.shade300),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 200, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Container(height: 12, width: double.infinity, color: Colors.grey.shade300),
                  const SizedBox(height: 4),
                  Container(height: 12, width: 250, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Container(height: 10, width: 100, color: Colors.grey.shade300),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

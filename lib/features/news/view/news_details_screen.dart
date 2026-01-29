import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repo/news_repo.dart';
import '../models/news_item.dart';

class NewsDetailScreen extends StatefulWidget {
  static const routeBase = '/news';
  static const subPath = ':id';
  static const routeName = 'newsDetail';

  final String newsId;
  const NewsDetailScreen({super.key, required this.newsId});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final _repo = NewsRepo();
  Future<NewsItem?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getById(widget.newsId);
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: FutureBuilder<NewsItem?>(
        future: _future,
        builder: (_, s) {
          if (s.connectionState == ConnectionState.waiting || !s.hasData) {
            return const _ShimmerDetail();
          }

          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error loading news.\n${s.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: () => setState(() => _future = _repo.getById(widget.newsId)), child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final n = s.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  n.imageUrl,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey.shade300, child: const Icon(Icons.broken_image)),
                ),
              ),
              const SizedBox(height: 16),
              Text(n.title, style: ts.headlineSmall),
              const SizedBox(height: 8),
              Text('${n.ts.day}/${n.ts.month}/${n.ts.year}', style: ts.bodySmall),
              const SizedBox(height: 16),

              // ✅ Rich HTML rendering
              HtmlRichText(html: n.summary),
            ],
          );
        },
      ),
    );
  }
}

/// 🔷 Shimmer skeleton loader
class _ShimmerDetail extends StatelessWidget {
  const _ShimmerDetail();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(height: 200, width: double.infinity, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Container(height: 20, width: 200, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 12, width: 100, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          for (int i = 0; i < 5; i++) ...[Container(height: 12, width: double.infinity, color: Colors.grey.shade300), const SizedBox(height: 8)],
        ],
      ),
    );
  }
}

/// 🌿 Minimal HTML renderer (bold, italic, links, paragraphs)
class HtmlRichText extends StatelessWidget {
  final String html;
  const HtmlRichText({super.key, required this.html});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme.bodyMedium!;
    final nodes = html_parser.parseFragment(html).nodes;

    List<TextSpan> spans = [];
    for (final node in nodes) {
      spans.addAll(_parseNode(node, ts, context));
      spans.add(const TextSpan(text: '\n\n')); // paragraph spacing
    }

    return RichText(text: TextSpan(style: ts.copyWith(height: 1.5, color: Colors.black87), children: spans));
  }

  List<TextSpan> _parseNode(dom.Node node, TextStyle base, BuildContext context) {
    if (node is dom.Text) {
      return [TextSpan(text: node.text)];
    } else if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      TextStyle style = base;

      // Apply formatting
      if (tag == 'b' || tag == 'strong') {
        style = base.copyWith(fontWeight: FontWeight.bold);
      } else if (tag == 'i' || tag == 'em') {
        style = base.copyWith(fontStyle: FontStyle.italic);
      } else if (tag == 'u') {
        style = base.copyWith(decoration: TextDecoration.underline);
      }

      // Handle links
      if (tag == 'a') {
        final href = node.attributes['href'];
        final linkText = node.text;
        return [
          TextSpan(
            text: linkText,
            style: base.copyWith(color: Colors.blue, decoration: TextDecoration.underline),
            recognizer:
                TapGestureRecognizer()
                  ..onTap = () async {
                    if (href != null) {
                      String url = href;
                      if (!url.startsWith('http://') && !url.startsWith('https://')) {
                        url = 'https://$url';
                      }
                      final uri = Uri.parse(url);

                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        print("Unable to open link: $url");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to open link: $url')));
                        }
                      }
                    }
                  },
          ),
        ];
      }

      // Recursively render children
      final children = node.nodes.expand((n) => _parseNode(n, style, context)).toList();
      return [TextSpan(children: children, style: style)];
    }
    return [];
  }
}

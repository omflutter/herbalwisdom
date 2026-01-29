import 'package:dio/dio.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news_item.dart';

class NewsRepo {
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, headers: {'Accept': 'application/json'}, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20)));

  static final List<NewsItem> _cache = [];

  /// Fetch all news articles (keeps HTML content for rich rendering)
  Future<List<NewsItem>> fetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Missing auth token. Please log in again.');

      final res = await _dio.get('/get-all-news', options: Options(headers: {'auth-token': token}));

      final data = res.data;
      if (data['status'] != "1") throw Exception(data['message'] ?? 'Failed to load news.');

      final List details = data['details'] ?? [];
      final news =
          details.map<NewsItem>((e) {
            final rawHtml = (e['body'] ?? '').toString(); // 👈 keep HTML intact
            return NewsItem(
              id: e['id'].toString(),
              title: (e['title'] ?? '').toString(),
              summary: rawHtml, // ✅ store HTML directly for formatted rendering
              imageUrl: (e['image'] ?? '').toString(),
              ts: DateTime.tryParse(e['date_time'] ?? '') ?? DateTime.now(),
            );
          }).toList();

      _cache
        ..clear()
        ..addAll(news);

      return news;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Error fetching news: $e');
    }
  }

  /// Get specific news item (cached or fetched)
  Future<NewsItem?> getById(String id) async {
    if (_cache.isEmpty) await fetch();
    try {
      return _cache.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }
}

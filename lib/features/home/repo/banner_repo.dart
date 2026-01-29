import 'package:dio/dio.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:herbalwisdom/features/home/models/banner_items.dart';


class BannersRepo {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      headers: {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  Future<List<BannerItem>> fetchAll() async {
    try {
      final res = await _dio.get('/get-banners');
      final data = res.data;

      if (data['status'] != "1") {
        throw Exception(data['message'] ?? 'Failed to load banners');
      }

      final List details = data['details'] ?? [];
      return details.map((e) => BannerItem.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Error fetching banners: $e');
    }
  }
}

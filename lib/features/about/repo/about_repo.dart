// lib/features/about/repo/about_repo.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:herbalwisdom/features/about/model/about_us_model.dart';



class AboutRepo {
  final Dio _dio;

  AboutRepo({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl, // e.g. https://herbal.robolaxy.com/medd/index.php/api
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 20),
                headers: {'Accept': 'application/json'},
              ),
            );

  Future<AboutUsDetails> getAboutUs() async {
    try {
      final resp = await _dio.get('/get-about-us');
      final data = resp.data is Map ? resp.data as Map<String, dynamic> : <String, dynamic>{};
      final parsed = AboutUsResponse.fromJson(data);

      if (parsed.isOk) {
        return parsed.details!;
      }
      throw Exception(parsed.message.isNotEmpty ? parsed.message : 'Failed to load About Us');
    } on DioException catch (e) {
      debugPrint('❌ [AboutRepo] /get-about-us error: ${e.message}');
      throw Exception('Network error while fetching About Us');
    } catch (e) {
      debugPrint('❌ [AboutRepo] Unknown error: $e');
      throw Exception('Unexpected error while fetching About Us');
    }
  }
}

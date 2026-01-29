import 'package:dio/dio.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vouchers.dart';

class VouchersRepo {
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, headers: {'Accept': 'application/json'}, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20)));

  static final List<Voucher> _cache = [];

  /// Fetch vouchers.
  ///
  /// `type` MUST be "ACTIVE" or "USED" (as required by API).
  Future<List<Voucher>> fetchAll({String type = 'ACTIVE'}) async {
    final typeUpper = type.toUpperCase(); // safety
    print("Selected Type: $typeUpper");
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) {
        throw Exception('Missing auth token. Please log in again.');
      }

      final res = await _dio.get('/get-specials-list', queryParameters: {'type': typeUpper}, options: Options(headers: {'auth-token': token}));

      final data = res.data;
      final status = (data['status'] ?? '').toString();

      if (status == "1") {
        final List details = data['details'] ?? [];
        final vouchers = details.map<Voucher>((e) => Voucher.fromJson(e as Map<String, dynamic>, listType: typeUpper)).toList();

        // Upsert into cache
        for (final v in vouchers) {
          final index = _cache.indexWhere((c) => c.id == v.id);
          if (index >= 0) {
            _cache[index] = v;
          } else {
            _cache.add(v);
          }
        }

        return vouchers;
      }

      // Many APIs return status "2" for "no data found"
      if (status == "0") {
        // Do not clear cache here, just return empty
        return <Voucher>[];
      }

      // Any other status is treated as a real error
      throw Exception(data['message'] ?? 'Failed to load vouchers');
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Error fetching vouchers: $e');
    }
  }

  Future<Voucher?> getById(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        final res = await _dio.get('/get-specials-by-id', queryParameters: {'voucher_id': id}, options: Options(headers: {'auth-token': token}));

        final data = res.data;
        if (data['status']?.toString() == '1') {
          final details = data['details'];
          if (details != null) {
            final v = Voucher.fromJson(Map<String, dynamic>.from(details));
            // Update cache
            final index = _cache.indexWhere((c) => c.id == v.id);
            if (index >= 0) {
              _cache[index] = v;
            } else {
              _cache.add(v);
            }
            return v;
          }
        }
      }
    } catch (e) {
      print('Error fetching voucher by id: $e');
    }

    // Fallback to cache
    try {
      return _cache.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> markUsed(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      final res = await _dio.post('/use-specials', data: FormData.fromMap({'voucher_id': id}), options: Options(headers: {'auth-token': token}));

      if (res.statusCode == 200 && res.data['status'] == "1") {
        final i = _cache.indexWhere((v) => v.id == id);
        if (i >= 0) {
          _cache[i].used = true; // locally mark as used
        }
        return;
      } else {
        throw Exception(res.data['message'] ?? 'Failed to mark as used');
      }
    } catch (e) {
      rethrow;
    }
  }
}

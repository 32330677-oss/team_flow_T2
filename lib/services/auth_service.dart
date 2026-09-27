import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl =
      'http://localhost:5002/api/auth/';

  static const FlutterSecureStorage storage = FlutterSecureStorage( );

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  /// تسجيل الدخول عبر Backend الموجود على Render
  Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await dio.post(
        'login',
        data: <String, dynamic>{
          'email': email.trim(),
          'password': password,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final responseData = Map<String, dynamic>.from(
        response.data as Map,
      );

      final token = responseData['token'];

      if (token == null || token.toString().trim().isEmpty) {
        print('Login succeeded, but no token was returned.');
        return responseData;
      }

      final prefs = await SharedPreferences.getInstance();

      // حذف أي Token قديم حتى لا يحدث تضارب بين الجلسات.
      await prefs.remove('token');
      await prefs.remove('jwt_token');

      // حفظ التوكن في التخزين الآمن فقط.
      await storage.write(
        key: 'jwt_token',
        value: token.toString(),
      );

      print('Token saved securely.');

      return responseData;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;

      print('Login failed. HTTP status: $statusCode');
      print('Login response: $responseData');

      return null;
    } catch (error) {
      print('Login error: $error');
      return null;
    }
  }

  /// قراءة التوكن المحفوظ عند فتح التطبيق.
  Future<String?> getToken() async {
    return storage.read(key: 'jwt_token');
  }

  /// حذف الجلسة الحالية عند تسجيل الخروج.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('jwt_token');
    await storage.delete(key: 'jwt_token');
  }
}

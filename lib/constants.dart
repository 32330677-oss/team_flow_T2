import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';

class ApiConfig {
  static const String baseUrl =
     'http://localhost:5002/api';

  static const FlutterSecureStorage storage = FlutterSecureStorage();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // ✅ الميثود الأصلية - ما تتغير، مستخدمة بزر Logout اليدوي
  static Future<void> logout() async {
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (route) => false);
    await storage.deleteAll();
  }

  // ✅ ميثود جديدة منفصلة - خاصة بحالة انتهاء صلاحية التوكن فقط
  static Future<void> _forceLogoutWithMessage(String message) async {
    await storage.delete(key: 'jwt_token');
    await storage.delete(key: 'user_role');
    await storage.delete(key: 'user_id');
    await storage.delete(key: 'user_name');

    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token = await storage.read(key: 'jwt_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },

        // ✅ هون التعديل الوحيد على الكود الموجود
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          bool isLoginRequest = error.requestOptions.path.contains('/login');
          final status = error.response?.statusCode;

          if (status == 401 && !isLoginRequest) {
            final data = error.response?.data;
            final code = data is Map ? data['code'] : null;

            final message = code == 'TOKEN_EXPIRED'
                ? 'Your session has expired. Please log in again.'
                : 'Session invalid. Please log in again.';

            await _forceLogoutWithMessage(message);
          }
          return handler.next(error);
        },
      ),
    );
}
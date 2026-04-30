import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'auth_models.dart';

class AuthApi {
  AuthApi(this._client);
  final DioClient _client;

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      return _parseResult(r);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthResult> login({required String email, required String password}) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return _parseResult(r);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _client.dio.post<Map<String, dynamic>>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AppUser> me() async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>('/auth/me');
      final data = r.data?['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw ApiException(r.statusCode ?? 0, 'BAD_RESPONSE', 'Empty response');
      }
      return AppUser.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  AuthResult _parseResult(Response<Map<String, dynamic>> r) {
    if (r.statusCode == null || r.statusCode! >= 400) {
      final err = (r.data?['error'] as Map?) ?? {};
      throw ApiException(
        r.statusCode ?? 0,
        err['code']?.toString() ?? 'UNKNOWN',
        err['message']?.toString() ?? 'Auth failed',
      );
    }
    final data = r.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw ApiException(r.statusCode ?? 0, 'BAD_RESPONSE', 'Empty response');
    }
    return AuthResult.fromJson(data);
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioClientProvider));
});

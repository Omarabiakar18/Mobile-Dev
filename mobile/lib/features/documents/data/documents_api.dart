import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'document_model.dart';

class DocumentsApi {
  DocumentsApi(this._client);
  final DioClient _client;

  Future<List<Document>> listForCar(String carId, {int page = 1, int limit = 20}) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/documents',
        queryParameters: {'page': page, 'limit': limit},
      );
      final raw = (r.data?['data']?['documents'] as List?) ?? const [];
      return raw.map((e) => Document.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Document> get(String id) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>('/documents/$id');
      return Document.fromJson(r.data!['data']['document'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Document> create({
    required String carId,
    required DocumentType type,
    required DateTime expiryDate,
    DateTime? issuedDate,
    String? issuer,
    String? notes,
    required String filePath,
    String? fileName,
  }) async {
    try {
      final form = FormData.fromMap({
        'type': type.name,
        'expiryDate': expiryDate.toIso8601String(),
        if (issuedDate != null) 'issuedDate': issuedDate.toIso8601String(),
        if (issuer != null && issuer.isNotEmpty) 'issuer': issuer,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars/$carId/documents',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Document.fromJson(r.data!['data']['document'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Document> update(String id, Map<String, dynamic> patch) async {
    try {
      final r = await _client.dio.patch<Map<String, dynamic>>(
        '/documents/$id',
        data: patch,
      );
      return Document.fromJson(r.data!['data']['document'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/documents/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<Document>> expiring(String carId, {int withinDays = 30}) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/documents/expiring',
        queryParameters: {'withinDays': withinDays},
      );
      final raw = (r.data?['data']?['documents'] as List?) ?? const [];
      return raw.map((e) => Document.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final documentsApiProvider = Provider<DocumentsApi>((ref) {
  return DocumentsApi(ref.watch(dioClientProvider));
});

/// Documents for a single car, ordered by `expiryDate asc` (server side).
/// Invalidate after create/update/delete to refresh the list.
final documentsListProvider =
    FutureProvider.family<List<Document>, String>((ref, carId) async {
  return ref.watch(documentsApiProvider).listForCar(carId);
});

/// Documents expiring within the default 30-day window — feeds the home
/// dashboard banner once Phase 2's home screen lands.
final expiringDocumentsProvider =
    FutureProvider.family<List<Document>, String>((ref, carId) async {
  return ref.watch(documentsApiProvider).expiring(carId);
});

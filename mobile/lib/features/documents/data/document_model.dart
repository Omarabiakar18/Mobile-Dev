import 'package:flutter/material.dart';

/// Mirrors the backend `DocumentType` enum (see `prisma/schema.prisma`).
enum DocumentType {
  insurance,
  mecanique,
  registration,
  other;

  static DocumentType fromString(String s) => DocumentType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => DocumentType.other,
      );

  String get label {
    switch (this) {
      case DocumentType.insurance:
        return 'Insurance';
      case DocumentType.mecanique:
        return 'Mécanique';
      case DocumentType.registration:
        return 'Registration';
      case DocumentType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case DocumentType.insurance:
        return Icons.security;
      case DocumentType.mecanique:
        return Icons.build;
      case DocumentType.registration:
        return Icons.description;
      case DocumentType.other:
        return Icons.folder;
    }
  }
}

class Document {
  Document({
    required this.id,
    required this.carId,
    required this.type,
    this.issuedDate,
    required this.expiryDate,
    required this.fileUrl,
    this.issuer,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String carId;
  final DocumentType type;
  final DateTime? issuedDate;
  final DateTime expiryDate;
  final String fileUrl;
  final String? issuer;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Days remaining until expiry — negative if already expired.
  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  bool get isExpired => daysUntilExpiry < 0;
  bool get isExpiringSoon => !isExpired && daysUntilExpiry <= 30;

  factory Document.fromJson(Map<String, dynamic> j) => Document(
        id: j['id'] as String,
        carId: j['carId'] as String,
        type: DocumentType.fromString(j['type'] as String),
        issuedDate: j['issuedDate'] == null
            ? null
            : DateTime.parse(j['issuedDate'] as String),
        expiryDate: DateTime.parse(j['expiryDate'] as String),
        fileUrl: j['fileUrl'] as String,
        issuer: j['issuer'] as String?,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'type': type.name,
        'issuedDate': issuedDate?.toIso8601String(),
        'expiryDate': expiryDate.toIso8601String(),
        'fileUrl': fileUrl,
        'issuer': issuer,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

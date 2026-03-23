/// 消息附件数据模型
///
/// SOLID: 独立数据类，不依赖 UI 或持久化层

import 'dart:convert';
import 'package:uuid/uuid.dart';

/// 附件类型
enum AttachmentType {
  image,  // 图片文件 (png/jpg/gif/webp)
  pdf,    // PDF 文档
  text,   // 纯文本文件
}

/// 消息附件
class MessageAttachment {
  final String id;
  final String fileName;
  final String filePath;       // 应用内存储路径
  final int fileSize;          // 字节数
  final AttachmentType type;
  final String mimeType;       // image/png, application/pdf, text/plain

  const MessageAttachment({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.type,
    required this.mimeType,
  });

  /// 创建附件（自动生成 ID）
  factory MessageAttachment.create({
    required String fileName,
    required String filePath,
    required int fileSize,
    required AttachmentType type,
    required String mimeType,
  }) {
    return MessageAttachment(
      id: 'att_${const Uuid().v4()}',
      fileName: fileName,
      filePath: filePath,
      fileSize: fileSize,
      type: type,
      mimeType: mimeType,
    );
  }

  /// 是否为图片
  bool get isImage => type == AttachmentType.image;

  /// 是否为 PDF
  bool get isPdf => type == AttachmentType.pdf;

  /// 人类可读的文件大小
  String get readableSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 根据文件扩展名推断附件类型
  static AttachmentType typeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
        return AttachmentType.image;
      case 'pdf':
        return AttachmentType.pdf;
      default:
        return AttachmentType.text;
    }
  }

  /// 根据文件扩展名推断 MIME 类型
  static String mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'bmp': return 'image/bmp';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'md': return 'text/markdown';
      default: return 'application/octet-stream';
    }
  }

  /// 创建修改后的副本
  MessageAttachment copyWith({
    String? filePath,
    String? fileName,
    int? fileSize,
  }) {
    return MessageAttachment(
      id: id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      type: type,
      mimeType: mimeType,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'fileName': fileName,
    'filePath': filePath,
    'fileSize': fileSize,
    'type': type.name,
    'mimeType': mimeType,
  };

  factory MessageAttachment.fromMap(Map<String, dynamic> map) =>
      MessageAttachment(
        id: map['id'] as String,
        fileName: map['fileName'] as String,
        filePath: map['filePath'] as String,
        fileSize: map['fileSize'] as int,
        type: AttachmentType.values.byName(map['type'] as String),
        mimeType: map['mimeType'] as String,
      );

  String toJson() => jsonEncode(toMap());
  factory MessageAttachment.fromJson(String source) =>
      MessageAttachment.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

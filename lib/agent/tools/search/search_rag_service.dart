/// 搜索结果 RAG 压缩服务
///
/// - 每个搜索结果仅保留 documentCount 个 chunk（默认 1）
/// - 先截断每个来源的内容（cutoff），再分块 embedding
/// - 余弦相似度 KNN
/// - Round Robin 选择（避免单源垄断）+ 按 sourceUrl 合并同源片段
///
/// SOLID: 单一职责 — 仅处理搜索结果的 RAG 压缩
/// 全程内存操作，不写数据库，用完即销毁。

import 'dart:math';

import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:flutter/foundation.dart';

/// RAG 压缩后的结果条目
class RagCompressedResult {
  final String title;
  final String url;
  final String content;
  final double avgScore;

  const RagCompressedResult({
    required this.title,
    required this.url,
    required this.content,
    this.avgScore = 0,
  });

  @override
  String toString() => '[$title]($url)\n$content';
}

/// 带来源信息的嵌入块
class _EmbeddedChunk {
  final String text;
  final String sourceUrl;
  final String sourceTitle;
  final List<double> embedding;

  _EmbeddedChunk({
    required this.text,
    required this.sourceUrl,
    required this.sourceTitle,
    required this.embedding,
  });
}

/// 搜索结果 RAG 压缩服务
class SearchRagService {
  // ── 核心限制常量 ───────────────────────────────────────
  // totalDocumentCount = rawResults.length × documentCount
  // 即：每个搜索结果只保留 1 个最相关的 chunk（极其保守）

  /// 每个来源最多保留的 chunk 数（documentCount=1）
  static const int _documentCountPerResult = 1;

  /// 分块大小上限（字符）
  static const int _maxChunkLength = 400;

  /// 重叠字符数
  static const int _chunkOverlap = 50;

  /// 每个来源页面内容截断上限（cutoff 模式）
  /// 先截断再分块，从根源限制 embedding 请求数量
  static const int _contentCutoffPerSource = 1500;

  /// 对搜索结果执行 RAG 压缩
  ///
  /// [query] — 用户原始查询
  /// [results] — 搜索结果列表 {title, url, content}
  /// [embeddingService] — 嵌入服务实例
  /// [totalMaxChunks] — 总共最多返回的片段数（Round Robin 选后）
  /// [maxChunksPerSource] — 每个来源最多选取的片段数（Round Robin 中）
  static Future<List<RagCompressedResult>> compress({
    required String query,
    required List<Map<String, String>> results,
    required EmbeddingService embeddingService,
    int maxChunksPerSource = 3,
    int totalMaxChunks = 10,
  }) async {
    if (results.isEmpty || !embeddingService.isConfigured) return [];

    // totalDocumentCount = resultCount * documentCount
    final maxEmbedTotal = results.length * _documentCountPerResult;
    debugPrint(
      'SearchRag: starting compression for ${results.length} results, '
      'maxEmbedTotal=$maxEmbedTotal',
    );

    // ── 步骤 1: 查询 embedding ──
    final queryEmbedding = await embeddingService.embedQuery(query);
    if (queryEmbedding == null) {
      debugPrint('SearchRag: query embedding failed');
      return [];
    }

    // ── 步骤 2: 截断 → 分块 → embedding ──
    final allChunks = <_EmbeddedChunk>[];

    for (final r in results) {
      final rawContent = r['content'] ?? r['snippet'] ?? '';
      final url = r['url'] ?? '';
      final title = r['title'] ?? '';
      if (rawContent.isEmpty) continue;

      // cutoff: 先截断内容，从源头限制分块数
      final content = rawContent.length > _contentCutoffPerSource
          ? rawContent.substring(0, _contentCutoffPerSource)
          : rawContent;

      final textChunks = _splitIntoChunks(content);

      // 每个来源只 embed documentCountPerResult 个 chunk
      int sourceEmbedded = 0;
      for (final chunkText in textChunks) {
        if (sourceEmbedded >= _documentCountPerResult) break;
        if (allChunks.length >= maxEmbedTotal) break;

        final embedding = await embeddingService.embedQuery(chunkText);
        if (embedding != null) {
          allChunks.add(
            _EmbeddedChunk(
              text: chunkText,
              sourceUrl: url,
              sourceTitle: title,
              embedding: embedding,
            ),
          );
          sourceEmbedded++;
        }
      }

      if (allChunks.length >= maxEmbedTotal) {
        debugPrint('SearchRag: reached embed limit ($maxEmbedTotal)');
        break;
      }
    }

    if (allChunks.isEmpty) {
      debugPrint('SearchRag: no valid chunks after embedding');
      return [];
    }

    debugPrint('SearchRag: ${allChunks.length} chunks embedded');

    // ── 步骤 3: 余弦相似度排序 ──
    final scored = allChunks.map((chunk) {
      final sim = _cosineSimilarity(queryEmbedding, chunk.embedding);
      return (chunk: chunk, score: sim);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    debugPrint(
      'SearchRag: top scores: '
      '${scored.take(5).map((s) => '${s.score.toStringAsFixed(3)}').join(', ')}',
    );

    // ── 步骤 4: Round Robin 选择 ──
    // selectReferences(rawResults, references, totalDocumentCount)
    final selected = _roundRobinSelect(
      scored: scored,
      urlOrder: results
          .map((r) => r['url'] ?? '')
          .where((u) => u.isNotEmpty)
          .toList(),
      maxTotal: totalMaxChunks,
      maxPerSource: maxChunksPerSource,
    );

    // ── 步骤 5: 按 sourceUrl 合并同源 ──
    // consolidateReferencesByUrl(rawResults, selectedReferences)
    return _consolidateByUrl(selected);
  }

  /// Round Robin 选择 — 按原始搜索结果顺序轮询
  static List<({_EmbeddedChunk chunk, double score})> _roundRobinSelect({
    required List<({_EmbeddedChunk chunk, double score})> scored,
    required List<String> urlOrder,
    required int maxTotal,
    required int maxPerSource,
  }) {
    // 按 URL 分组，每组内已按分数排序
    final groups = <String, List<({_EmbeddedChunk chunk, double score})>>{};
    for (final s in scored) {
      groups.putIfAbsent(s.chunk.sourceUrl, () => []).add(s);
    }

    final selected = <({_EmbeddedChunk chunk, double score})>[];
    int roundIndex = 0;

    // 按原始搜索结果顺序排列活跃 URL
    final seen = <String>{};
    final activeUrls = urlOrder.where((u) {
      if (seen.contains(u) || !groups.containsKey(u)) return false;
      seen.add(u);
      return true;
    }).toList();

    while (selected.length < maxTotal && activeUrls.isNotEmpty) {
      if (roundIndex >= activeUrls.length) roundIndex = 0;

      final url = activeUrls[roundIndex];
      final group = groups[url]!;

      if (group.isNotEmpty) {
        selected.add(group.removeAt(0));
      }

      if (group.isEmpty) {
        activeUrls.removeAt(roundIndex);
        if (roundIndex >= activeUrls.length) roundIndex = 0;
      } else {
        roundIndex++;
      }
    }

    return selected;
  }

  /// 按 sourceUrl 合并同源片段
  static List<RagCompressedResult> _consolidateByUrl(
    List<({_EmbeddedChunk chunk, double score})> selected,
  ) {
    final groups = <String, List<({_EmbeddedChunk chunk, double score})>>{};
    final titles = <String, String>{};

    for (final s in selected) {
      groups.putIfAbsent(s.chunk.sourceUrl, () => []).add(s);
      titles.putIfAbsent(s.chunk.sourceUrl, () => s.chunk.sourceTitle);
    }

    return groups.entries.map((e) {
      final avgScore =
          e.value.fold<double>(0, (sum, s) => sum + s.score) / e.value.length;
      return RagCompressedResult(
        title: titles[e.key] ?? '',
        url: e.key,
        content: e.value.map((s) => s.chunk.text).join('\n\n---\n\n'),
        avgScore: avgScore,
      );
    }).toList();
  }

  /// 文本分块 — 在句号/换行处优先断开
  static List<String> _splitIntoChunks(String text) {
    if (text.length <= _maxChunkLength) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = start + _maxChunkLength;
      if (end > text.length) end = text.length;

      // 尝试在自然断点处断开
      if (end < text.length) {
        final breakPoints = ['\n\n', '。', '. ', '\n', '，', ', '];
        for (final bp in breakPoints) {
          final pos = text.lastIndexOf(bp, end);
          if (pos > start + _maxChunkLength * 0.5) {
            end = pos + bp.length;
            break;
          }
        }
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);

      if (end >= text.length) break;

      start = end - _chunkOverlap;
      if (start >= text.length) break;
    }

    return chunks;
  }

  /// 余弦相似度
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0) return 0;
    return dot / denom;
  }
}

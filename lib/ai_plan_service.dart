import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'template_store.dart';

class AIPlanService {
  AIPlanService({required this.store});

  final TemplateStore store;

  Future<List<TrainingAction>> generatePlan({
    required String folderName,
    required String templateName,
    required String intent,
  }) async {
    final config = await store.loadModelConfig();
    final baseUrl = (config['baseUrl'] ?? '').trim();
    final modelName = (config['modelName'] ?? '').trim();
    final apiKey = (config['apiKey'] ?? '').trim();

    if (baseUrl.isEmpty || modelName.isEmpty || apiKey.isEmpty) {
      throw Exception('请先在模型配置页填写 baseUrl、modelName、apiKey');
    }

    final promptTemplate = await rootBundle.loadString('assets/prompts/plan_generate_prompt.txt');
    final prompt = promptTemplate
        .replaceAll('{{folder_name}}', folderName)
        .replaceAll('{{template_name}}', templateName)
        .replaceAll('{{intent}}', intent);

    final endpoint = baseUrl.endsWith('/') ? '${baseUrl}chat/completions' : '$baseUrl/chat/completions';
    debugPrint('[AIPlanService] generatePlan start');
    debugPrint('[AIPlanService] endpoint=$endpoint');
    debugPrint('[AIPlanService] folder=$folderName template=$templateName intentLength=${intent.length}');
    debugPrint('[AIPlanService] model=$modelName apiKeyMasked=${_maskKey(apiKey)}');

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': modelName,
        'temperature': 0.4,
        'messages': [
          {'role': 'system', 'content': '你是健身训练计划生成助手。只输出JSON。'},
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    debugPrint('[AIPlanService] httpStatus=${response.statusCode}');
    debugPrint('[AIPlanService] responsePreview=${_preview(response.body, 800)}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('模型调用失败：HTTP ${response.statusCode} ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = _extractModelText(body);
    debugPrint('[AIPlanService] extractedContentLength=${content.length}');
    debugPrint('[AIPlanService] extractedContentPreview=${_preview(content, 400)}');
    if (content.isEmpty) {
      final preview = response.body.length > 300 ? '${response.body.substring(0, 300)}...' : response.body;
      throw Exception('模型未返回内容，响应片段: $preview');
    }

    final jsonText = _extractJson(content);
    debugPrint('[AIPlanService] extractedJsonLength=${jsonText.length}');
    debugPrint('[AIPlanService] extractedJsonPreview=${_preview(jsonText, 400)}');
    final generated = jsonDecode(jsonText) as Map<String, dynamic>;
    final actionsRaw = generated['actions'] as List<dynamic>? ?? [];
    debugPrint('[AIPlanService] actionsRawCount=${actionsRaw.length}');
    final actions = actionsRaw.map((e) => TrainingAction.fromJson(e as Map<String, dynamic>)).toList();
    if (actions.isEmpty) {
      throw Exception('模型未生成动作数据');
    }
    return _normalize(actions);
  }

  List<TrainingAction> _normalize(List<TrainingAction> actions) {
    for (final action in actions) {
      var alternatives = 0;
      for (final card in action.cards) {
        card.keyPoints = card.keyPoints.take(5).toList();
        card.commonMistakes = card.commonMistakes.take(5).toList();
        if (!card.isPrimary) {
          alternatives++;
        }
      }
      if (alternatives > 3) {
        final primary = action.cards.where((c) => c.isPrimary).toList();
        final alts = action.cards.where((c) => !c.isPrimary).take(3).toList();
        action.cards = [...primary, ...alts];
      }
    }
    return actions;
  }

  String _extractJson(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) return trimmed;
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final match = fence.firstMatch(trimmed);
    if (match != null) return match.group(1)!.trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) return trimmed.substring(start, end + 1);
    throw Exception('无法解析模型返回JSON');
  }

  String _extractModelText(Map<String, dynamic> body) {
    debugPrint('[AIPlanService] extractModelText begin keys=${body.keys.toList()}');
    final choices = body['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      debugPrint('[AIPlanService] extractModelText using choices branch count=${choices.length}');
      final first = choices.first as Map<String, dynamic>? ?? {};
      final message = first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final content = message['content'];
        final fromMessage = _normalizeContentValue(content);
        debugPrint('[AIPlanService] choices.message.contentType=${content.runtimeType} length=${fromMessage.length}');
        if (fromMessage.isNotEmpty) return fromMessage;
      }
      final text = first['text']?.toString() ?? '';
      debugPrint('[AIPlanService] choices.textLength=${text.length}');
      if (text.isNotEmpty) return text;
    }

    final output = body['output'] as List<dynamic>?;
    if (output != null && output.isNotEmpty) {
      debugPrint('[AIPlanService] extractModelText using output branch count=${output.length}');
      final firstOutput = output.first as Map<String, dynamic>? ?? {};
      final content = firstOutput['content'] as List<dynamic>?;
      if (content != null) {
        for (final item in content) {
          final map = item as Map<String, dynamic>;
          final text = map['text']?.toString() ?? '';
          debugPrint('[AIPlanService] output.content item textLength=${text.length}');
          if (text.isNotEmpty) return text;
        }
      }
    }

    debugPrint('[AIPlanService] extractModelText no usable content');
    return '';
  }

  String _normalizeContentValue(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List<dynamic>) {
      final parts = <String>[];
      for (final item in content) {
        if (item is String) {
          parts.add(item);
          continue;
        }
        if (item is Map<String, dynamic>) {
          final text = item['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            parts.add(text);
            continue;
          }
          final inner = item['content']?.toString() ?? '';
          if (inner.isNotEmpty) {
            parts.add(inner);
          }
        }
      }
      return parts.join('\n').trim();
    }
    return content.toString();
  }

  String _preview(String text, int max) {
    final t = text.replaceAll('\n', '\\n');
    return t.length <= max ? t : '${t.substring(0, max)}...';
  }

  String _maskKey(String key) {
    if (key.length <= 8) return '***';
    return '${key.substring(0, 4)}***${key.substring(key.length - 4)}';
  }
}

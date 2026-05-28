import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';

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

    final promptTemplate = await rootBundle.loadString(
      'assets/prompts/plan_generate_prompt.txt',
    );
    final prompt = promptTemplate
        .replaceAll('{{folder_name}}', folderName)
        .replaceAll('{{template_name}}', templateName)
        .replaceAll('{{intent}}', intent);

    final cleanBaseUrl = baseUrl.endsWith('/chat/completions')
        ? baseUrl.substring(0, baseUrl.length - '/chat/completions'.length)
        : baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    debugPrint('[AIPlanService] generatePlan start');
    debugPrint('[AIPlanService] baseUrl=$cleanBaseUrl');
    debugPrint(
      '[AIPlanService] folder=$folderName template=$templateName intentLength=${intent.length}',
    );
    debugPrint(
      '[AIPlanService] model=$modelName apiKeyMasked=${_maskKey(apiKey)}',
    );

    final chat = ChatOpenAI(
      apiKey: apiKey,
      baseUrl: cleanBaseUrl,
      defaultOptions: ChatOpenAIOptions(model: modelName, temperature: 0.4),
    );

    final messages = [
      ChatMessage.system('你是健身训练计划生成助手。只输出JSON。'),
      ChatMessage.humanText(prompt),
    ];

    late final String content;
    try {
      final aiMessage = await chat.call(messages);
      content = aiMessage.content as String;
    } catch (e, s) {
      debugPrint('[AIPlanService] 模型调用失败: $e');
      debugPrint('[AIPlanService] 模型调用堆栈: $s');
      throw Exception('模型调用失败：$e');
    }

    debugPrint('[AIPlanService] responseLength=${content.length}');
    debugPrint('[AIPlanService] responsePreview=${_preview(content, 800)}');

    if (content.isEmpty) {
      throw Exception('模型未返回内容');
    }

    final jsonText = _extractJson(content);
    debugPrint('[AIPlanService] extractedJsonLength=${jsonText.length}');
    debugPrint(
      '[AIPlanService] extractedJsonPreview=${_preview(jsonText, 400)}',
    );

    final generated = jsonDecode(jsonText) as Map<String, dynamic>;
    final actionsRaw = generated['actions'] as List<dynamic>? ?? [];
    debugPrint('[AIPlanService] actionsRawCount=${actionsRaw.length}');

    final actions = actionsRaw
        .where((e) => e != null)
        .map((e) => TrainingAction.fromJson(e as Map<String, dynamic>))
        .toList();
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
        card.primaryMuscles = card.primaryMuscles.take(3).toList();
        card.secondaryMuscles = card.secondaryMuscles.take(3).toList();
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

  String _preview(String text, int max) {
    final t = text.replaceAll('\n', '\\n');
    return t.length <= max ? t : '${t.substring(0, max)}...';
  }

  Future<String> evaluateWorkout(WorkoutSession session) async {
    final config = await store.loadModelConfig();
    final baseUrl = (config['baseUrl'] ?? '').trim();
    final modelName = (config['modelName'] ?? '').trim();
    final apiKey = (config['apiKey'] ?? '').trim();

    if (baseUrl.isEmpty || modelName.isEmpty || apiKey.isEmpty) {
      throw Exception('请先在模型配置页填写 baseUrl、modelName、apiKey');
    }

    // 构建动作详情文本
    final buffer = StringBuffer();
    for (final e in session.exercises) {
      for (int i = 0; i < e.sets.length; i++) {
        final s = e.sets[i];
        final feelingText = e.feeling?.label ?? '未记录';
        buffer.writeln(
          '${e.groupTitle} - ${e.cardName}: ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次, 休息${s.restSec}秒, 感受: $feelingText',
        );
      }
    }

    final promptTemplate = await rootBundle.loadString(
      'assets/prompts/workout_evaluate_prompt.txt',
    );
    final prompt = promptTemplate
        .replaceAll('{{template_name}}', session.templateName)
        .replaceAll('{{duration}}', session.durationText)
        .replaceAll('{{total_sets}}', '${session.totalCount}')
        .replaceAll('{{exercise_details}}', buffer.toString().trim());

    final cleanBaseUrl = baseUrl.endsWith('/chat/completions')
        ? baseUrl.substring(0, baseUrl.length - '/chat/completions'.length)
        : baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final chat = ChatOpenAI(
      apiKey: apiKey,
      baseUrl: cleanBaseUrl,
      defaultOptions: ChatOpenAIOptions(model: modelName, temperature: 0.5),
    );

    final messages = [
      ChatMessage.system('你是专业的健身训练评估助手。用简体中文回复。'),
      ChatMessage.humanText(prompt),
    ];

    final aiMessage = await chat.call(messages);
    return aiMessage.content as String;
  }

  String _maskKey(String key) {
    if (key.length <= 8) return '***';
    return '${key.substring(0, 4)}***${key.substring(key.length - 4)}';
  }
}

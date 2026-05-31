import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';
import 'workout_state_manager.dart';

class PlanGenerationResult {
  PlanGenerationResult({required this.actions, this.summary = ''});
  final List<TrainingAction> actions;
  final String summary;
}

class AIPlanService {
  AIPlanService({required this.store});

  final TemplateStore store;

  Future<PlanGenerationResult> generatePlan({
    required String folderName,
    required String templateName,
    required String intent,
    String preferParts = '',
    String currentTemplateJson = '',
    String dialogAbilities = '',
    String dialogPreferences = '',
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
    var prompt = promptTemplate
        .replaceAll('{{folder_name}}', folderName)
        .replaceAll('{{template_name}}', templateName)
        .replaceAll('{{intent}}', intent);

    // 填充用户信息占位符（对话框选择优先，否则使用基础配置，最后用默认值）
    final userGender = ((config['userGender'] as String?) ?? '').trim();
    final userHeight = ((config['userHeight'] as String?) ?? '').trim();
    final userWeight = ((config['userWeight'] as String?) ?? '').trim();
    final userExperience = dialogAbilities.isNotEmpty
        ? dialogAbilities
        : ((config['userExperience'] as String?) ?? '').trim();
    final userPreferTools = dialogPreferences.isNotEmpty
        ? dialogPreferences
        : ((config['userPreferTools'] as String?) ?? '').trim();

    prompt = prompt
        .replaceAll(
          '{{user_gender}}',
          userGender.isNotEmpty ? userGender : '未设置',
        )
        .replaceAll(
          '{{user_high}}',
          userHeight.isNotEmpty ? '$userHeight cm' : '未设置',
        )
        .replaceAll(
          '{{user_weight}}',
          userWeight.isNotEmpty ? '$userWeight kg' : '未设置',
        )
        .replaceAll(
          '{{user_experience}}',
          userExperience.isNotEmpty ? userExperience : '未设置',
        )
        .replaceAll(
          '{{user_prefer_tools}}',
          userPreferTools.isNotEmpty ? userPreferTools : '未设置',
        );

    // 填充 {{user_prefer_parts}}
    prompt = prompt.replaceAll(
      '{{user_prefer_parts}}',
      preferParts.isNotEmpty ? '训练部位：$preferParts' : '用户未指定训练部位',
    );

    // 填充 {{current_template}}
    prompt = prompt.replaceAll(
      '{{current_template}}',
      currentTemplateJson.isNotEmpty ? currentTemplateJson : '（暂无训练模板）',
    );

    // 填充 {{user_preference}}
    final userPreference = (config['userPreference'] as String?)?.trim() ?? '';
    if (userPreference.isNotEmpty) {
      prompt = prompt.replaceAll('{{user_preference}}', userPreference);
    } else {
      prompt = prompt.replaceAll(
        RegExp(r'\n- 用户偏好\(.*?\): \{\{user_preference\}\}'),
        '',
      );
    }

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
      final aiMessage = await chat
          .call(messages)
          .timeout(const Duration(seconds: 90));
      content = aiMessage.content;
      LlmLogSaver.save(prompt, content);
    } on TimeoutException {
      debugPrint('[AIPlanService] 模型调用超时');
      throw Exception('模型调用超时，请检查网络或模型服务状态');
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
    final summaryText = generated['summary'] as String? ?? '';
    debugPrint('[AIPlanService] actionsRawCount=${actionsRaw.length}');
    debugPrint(
      '[AIPlanService] summary=${summaryText.isNotEmpty ? summaryText : "(空)"}',
    );

    final actions = actionsRaw
        .where((e) => e != null)
        .map((e) => TrainingAction.fromJson(e as Map<String, dynamic>))
        .toList();
    if (actions.isEmpty) {
      throw Exception('模型未生成动作数据');
    }
    return PlanGenerationResult(
      actions: _normalize(actions),
      summary: summaryText,
    );
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

  Future<WorkoutEvaluation?> evaluateWorkout({
    required WorkoutSession session,
    required TrainingTemplate template,
    WorkoutSession? lastSession,
  }) async {
    final config = await store.loadModelConfig();
    final baseUrl = (config['baseUrl'] ?? '').trim();
    final modelName = (config['modelName'] ?? '').trim();
    final apiKey = (config['apiKey'] ?? '').trim();

    if (baseUrl.isEmpty || modelName.isEmpty || apiKey.isEmpty) {
      throw Exception('请先在模型配置页填写 baseUrl、modelName、apiKey');
    }

    // 构建 template_content
    final tplBuffer = StringBuffer();
    for (final a in template.actions) {
      tplBuffer.writeln('## ${a.groupTitle}');
      for (final c in a.cards) {
        tplBuffer.writeln('  ${c.isPrimary ? "[主动作]" : "[平替]"} ${c.name}');
        for (final s in c.sets) {
          tplBuffer.writeln(
            '    组: ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次, 休息${s.restSec}秒',
          );
        }
      }
    }

    // 构建 exercise_details
    final buffer = StringBuffer();
    for (final e in session.exercises) {
      for (int i = 0; i < e.sets.length; i++) {
        final s = e.sets[i];
        final feelingText = e.feeling?.label ?? '未记录';
        final compText = e.compensation != null
            ? ', 代偿: ${e.compensation}'
            : '';
        buffer.writeln(
          '${e.groupTitle} - ${e.cardName}: ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次, 休息${s.restSec}秒, 感受: $feelingText$compText',
        );
      }
    }

    // 构建 last session 数据
    final lastBuffer = StringBuffer();
    if (lastSession != null) {
      for (final e in lastSession.exercises) {
        for (final s in e.sets) {
          final feelingText = e.feeling?.label ?? '未记录';
          final compText = e.compensation != null
              ? ', 代偿: ${e.compensation}'
              : '';
          lastBuffer.writeln(
            '${e.groupTitle} - ${e.cardName}: ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次, 休息${s.restSec}秒, 感受: $feelingText$compText',
          );
        }
      }
    }

    final promptTemplate = await rootBundle.loadString(
      'assets/prompts/workout_evaluate_prompt.txt',
    );
    var prompt = promptTemplate
        .replaceAll('{{folder_name}}', template.folder)
        .replaceAll('{{template_name}}', template.name)
        .replaceAll('{{duration}}', session.durationText)
        .replaceAll('{{total_sets}}', '${session.totalCount}')
        .replaceAll('{{template_content}}', tplBuffer.toString().trim())
        .replaceAll('{{exercise_details}}', buffer.toString().trim());

    if (lastSession != null) {
      prompt = prompt.replaceAll(
        '{{exercise_details_last_time}}',
        lastBuffer.toString().trim(),
      );
    } else {
      prompt = prompt.replaceAll(
        RegExp(r'\n上次训练数据:\s*\n\s*\{\{exercise_details_last_time\}\}\s*'),
        '',
      );
    }

    final userPreference = (config['userPreference'] as String?)?.trim() ?? '';
    if (userPreference.isNotEmpty) {
      prompt = prompt.replaceAll('{{user_preference}}', userPreference);
    } else {
      prompt = prompt.replaceAll(
        RegExp(r'\n用户偏好\(按这些要求来评价和建议\):\s*\n\s*\{\{user_preference\}\}\s*'),
        '',
      );
    }

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

    final aiMessage = await chat
        .call(messages)
        .timeout(const Duration(seconds: 90));
    final content = aiMessage.content;

    LlmLogSaver.save(prompt, content);

    if (content.isEmpty) return null;

    try {
      final jsonText = _extractJson(content);
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return WorkoutEvaluation.fromJson(parsed);
    } catch (e) {
      debugPrint('[evaluateWorkout] 解析JSON失败: $e');
      return null;
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8) return '***';
    return '${key.substring(0, 4)}***${key.substring(key.length - 4)}';
  }
}

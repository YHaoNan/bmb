import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'workout_models.dart';

class TemplateStore {
  static const templatesKey = 'bmb_templates';
  static const draftKey = 'bmb_template_draft';
  static const foldersKey = 'bmb_template_folders';
  static const modelConfigKey = 'bmb_model_config';
  static const workoutsKey = 'bmb_workouts';

  Future<List<TrainingTemplate>> loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(templatesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => TrainingTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTemplates(List<TrainingTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      templatesKey,
      jsonEncode(templates.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<String>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(foldersKey);
    return (data == null) ? <String>[] : data;
  }

  Future<void> saveFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(foldersKey, folders);
  }

  Future<TemplateDraft?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(draftKey);
    if (raw == null || raw.isEmpty) return null;
    return TemplateDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDraft(TemplateDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(draftKey, jsonEncode(draft.toJson()));
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey);
  }

  Future<Map<String, String>> loadModelConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(modelConfigKey);
    if (raw == null || raw.isEmpty) {
      return {'baseUrl': '', 'modelName': '', 'apiKey': ''};
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'baseUrl': data['baseUrl']?.toString() ?? '',
      'modelName': data['modelName']?.toString() ?? '',
      'apiKey': data['apiKey']?.toString() ?? '',
    };
  }

  Future<void> saveModelConfig({
    required String baseUrl,
    required String modelName,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      modelConfigKey,
      jsonEncode({
        'baseUrl': baseUrl,
        'modelName': modelName,
        'apiKey': apiKey,
      }),
    );
  }

  Future<List<WorkoutSession>> loadWorkouts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(workoutsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => WorkoutSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveWorkouts(List<WorkoutSession> workouts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      workoutsKey,
      jsonEncode(workouts.map((e) => e.toJson()).toList()),
    );
  }
}

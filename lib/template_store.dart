import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'workout_models.dart';

class TemplateStore {
  static Database? _db;
  static const _dbName = 'bmb_data.db';
  static const _dbVersion = 2;

  Future<Database> get _database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_dbName';
    await _migrateFromPrefs(dir);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrateDb(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS templates (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        name TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS draft (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS model_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_sessions (
        id TEXT PRIMARY KEY,
        template_id TEXT,
        template_name TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        ai_summary TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        group_title TEXT NOT NULL,
        card_name TEXT NOT NULL,
        exercise_name TEXT NOT NULL,
        is_alternative INTEGER NOT NULL DEFAULT 0,
        set_index INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        reps INTEGER NOT NULL,
        rest_sec INTEGER NOT NULL,
        feeling TEXT,
        compensation TEXT,
        notes TEXT,
        weight_modified INTEGER NOT NULL DEFAULT 0,
        reps_modified INTEGER NOT NULL DEFAULT 0,
        rest_modified INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workout_sets_session
      ON workout_sets(session_id)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS active_workout (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
  }

  // ─── Templates ───

  Future<List<TrainingTemplate>> loadTemplates() async {
    final db = await _database;
    final rows = await db.query('templates');
    return rows
        .map((r) =>
            TrainingTemplate.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTemplates(List<TrainingTemplate> templates) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('templates');
    for (final t in templates) {
      batch.insert('templates', {'id': t.id, 'data': jsonEncode(t.toJson())});
    }
    await batch.commit(noResult: true);
  }

  // ─── Folders ───

  Future<List<String>> loadFolders() async {
    final db = await _database;
    final rows = await db.query('folders');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> saveFolders(List<String> folders) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('folders');
    for (final f in folders) {
      batch.insert('folders', {'name': f});
    }
    await batch.commit(noResult: true);
  }

  // ─── Draft ───

  Future<TemplateDraft?> loadDraft() async {
    final db = await _database;
    final rows = await db.query('draft', where: 'id = 1');
    if (rows.isEmpty) return null;
    return TemplateDraft.fromJson(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<void> saveDraft(TemplateDraft draft) async {
    final db = await _database;
    await db.insert(
      'draft',
      {'id': 1, 'data': jsonEncode(draft.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDraft() async {
    final db = await _database;
    await db.delete('draft', where: 'id = 1');
  }

  // ─── Model Config ───

  Future<Map<String, String>> loadModelConfig() async {
    final db = await _database;
    final rows = await db.query('model_config', where: 'id = 1');
    if (rows.isEmpty) {
      return {'baseUrl': '', 'modelName': '', 'apiKey': ''};
    }
    final data = jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
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
    final db = await _database;
    await db.insert(
      'model_config',
      {
        'id': 1,
        'data': jsonEncode({
          'baseUrl': baseUrl,
          'modelName': modelName,
          'apiKey': apiKey,
        }),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── Workouts (relational) ───

  Future<List<WorkoutSession>> loadSessions() async {
    final db = await _database;
    // 用子查询一次性带出每组 session 的 set 数和有感觉得 set 数
    final rows = await db.rawQuery('''
      SELECT ws.*,
        (SELECT COUNT(*) FROM workout_sets WHERE session_id = ws.id) AS set_count,
        (SELECT COUNT(*) FROM workout_sets WHERE session_id = ws.id AND feeling IS NOT NULL) AS feeling_count
      FROM workout_sessions ws
      ORDER BY ws.start_time DESC
    ''');
    return rows.map((r) => WorkoutSession(
      id: r['id'] as String,
      startTime: DateTime.parse(r['start_time'] as String),
      endTime: r['end_time'] != null ? DateTime.parse(r['end_time'] as String) : null,
      templateId: r['template_id'] as String? ?? '',
      templateName: r['template_name'] as String? ?? '',
      totalSets: r['set_count'] as int?,
      completedSets: r['feeling_count'] as int?,
      aiSummary: r['ai_summary'] as String?,
    )).toList();
  }

  Future<WorkoutSession?> loadFullSession(String sessionId) async {
    final db = await _database;
    final rows = await db.query('workout_sessions', where: 'id = ?', whereArgs: [sessionId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final sets = await db.query('workout_sets',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'set_index');
    final exercises = sets.map((s) => ExerciseRecord(
      groupTitle: s['group_title'] as String? ?? '',
      cardName: s['card_name'] as String? ?? '',
      isAlternative: (s['is_alternative'] as int?) == 1,
      weightModified: (s['weight_modified'] as int?) == 1,
      repsModified: (s['reps_modified'] as int?) == 1,
      restModified: (s['rest_modified'] as int?) == 1,
      feeling: s['feeling'] != null ? Feeling.values.byName(s['feeling'] as String) : null,
      compensation: s['compensation'] as String?,
      notes: s['notes'] as String?,
      sets: [SetRecord(
        weightKg: (s['weight_kg'] as num?)?.toDouble() ?? 0,
        reps: (s['reps'] as int?) ?? 0,
        restSec: (s['rest_sec'] as int?) ?? 0,
      )],
    )).toList();
    return WorkoutSession(
      id: r['id'] as String,
      startTime: DateTime.parse(r['start_time'] as String),
      endTime: r['end_time'] != null ? DateTime.parse(r['end_time'] as String) : null,
      templateId: r['template_id'] as String? ?? '',
      templateName: r['template_name'] as String? ?? '',
      aiSummary: r['ai_summary'] as String?,
      exercises: exercises,
    );
  }

  Future<void> saveWorkoutSession(WorkoutSession session) async {
    final db = await _database;
    await _ensureAiSummaryColumn(db);
    await db.transaction((txn) async {
      await txn.insert('workout_sessions', {
        'id': session.id,
        'template_id': session.templateId,
        'template_name': session.templateName,
        'start_time': session.startTime.toIso8601String(),
        'end_time': session.endTime?.toIso8601String(),
        'ai_summary': session.aiSummary,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('workout_sets', where: 'session_id = ?', whereArgs: [session.id]);
      final batch = txn.batch();
      for (int i = 0; i < session.exercises.length; i++) {
        final e = session.exercises[i];
        for (int j = 0; j < e.sets.length; j++) {
          final s = e.sets[j];
          batch.insert('workout_sets', {
            'session_id': session.id,
            'group_title': e.groupTitle,
            'card_name': e.cardName,
            'exercise_name': e.cardName,
            'is_alternative': e.isAlternative ? 1 : 0,
            'set_index': i * 100 + j,
            'weight_kg': s.weightKg,
            'reps': s.reps,
            'rest_sec': s.restSec,
            'feeling': e.feeling?.name,
            'compensation': e.compensation,
            'notes': e.notes,
            'weight_modified': e.weightModified ? 1 : 0,
            'reps_modified': e.repsModified ? 1 : 0,
            'rest_modified': e.restModified ? 1 : 0,
          });
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _database;
    await db.delete('workout_sets', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('workout_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // ─── Active Workout ───

  /// 确保 active_workout 表存在（兼容旧 DB 文件缺失该表的情况）
  Future<void> _ensureActiveWorkoutTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS active_workout (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
  }

  /// 兼容旧 DB 文件缺失 ai_summary 列的情况
  Future<void> _ensureAiSummaryColumn(Database db) async {
    try {
      await db.execute('ALTER TABLE workout_sessions ADD COLUMN ai_summary TEXT');
    } catch (_) {}
  }

  Future<void> saveActiveWorkout(String json) async {
    final db = await _database;
    await _ensureActiveWorkoutTable(db);
    await db.insert(
      'active_workout',
      {'id': 1, 'data': json},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> loadActiveWorkout() async {
    final db = await _database;
    await _ensureActiveWorkoutTable(db);
    final rows = await db.query('active_workout', where: 'id = 1');
    if (rows.isEmpty) return null;
    return rows.first['data'] as String;
  }

  Future<void> clearActiveWorkout() async {
    final db = await _database;
    await _ensureActiveWorkoutTable(db);
    await db.delete('active_workout', where: 'id = 1');
  }

  // ─── 备份 ───

  static const _backupDirName = 'backups';
  static const _backupPrefix = 'bmb_back_';

  /// 备份目录路径
  Future<String> get _backupDirPath async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/$_backupDirName');
    if (!backupDir.existsSync()) backupDir.createSync();
    return backupDir.path;
  }

  /// 全量导出为 JSON 备份文件，保存到备份目录。
  /// 返回备份文件路径。
  Future<String> exportBackupJson() async {
    final db = await _database;

    final templates = (await db.query('templates'))
        .map((r) => jsonDecode(r['data'] as String))
        .toList();

    final folders =
        (await db.query('folders')).map((r) => r['name'] as String).toList();

    final draftRows = await db.query('draft', where: 'id = 1');
    final draft =
        draftRows.isNotEmpty ? jsonDecode(draftRows.first['data'] as String) : null;

    final configRows = await db.query('model_config', where: 'id = 1');
    final modelConfig = configRows.isNotEmpty
        ? jsonDecode(configRows.first['data'] as String)
        : null;

    final sessions = await db.query('workout_sessions');
    final sessionIds = sessions.map((r) => r['id'] as String).toList();
    final allSets = sessionIds.isNotEmpty
        ? await db.query('workout_sets',
            where: 'session_id IN (${sessionIds.map((_) => '?').join(',')})',
            whereArgs: sessionIds)
        : <Map<String, dynamic>>[];

    final now = DateTime.now();
    final ts = '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final fileName = '$_backupPrefix$ts.json';

    final backupDir = await _backupDirPath;
    final file = File('$backupDir/$fileName');
    file.writeAsStringSync(jsonEncode({
      'version': 2,
      'exportedAt': now.toIso8601String(),
      'data': {
        'templates': templates,
        'folders': folders,
        'draft': draft,
        'modelConfig': modelConfig,
        'sessions': sessions,
        'sets': allSets,
      },
    }));
    return file.path;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 列出所有备份文件，按时间戳倒序。
  Future<List<FileSystemEntity>> listBackups() async {
    final backupDir = await _backupDirPath;
    final dir = Directory(backupDir);
    if (!dir.existsSync()) return [];
    final files = dir.listSync().where((e) {
      if (e is! File) return false;
      return e.path.split('\\').last.split('/').last.startsWith(_backupPrefix) &&
          e.path.endsWith('.json');
    }).toList();
    files.sort((a, b) {
      return (b as File).lastModifiedSync().compareTo(
          (a as File).lastModifiedSync());
    });
    return files;
  }

  /// 删除备份文件
  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) await file.delete();
  }

  /// 从 JSON 备份文件恢复全部数据。
  /// 返回恢复是否成功。
  Future<bool> restoreFromJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;

      final raw = file.readAsStringSync();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final content = data['data'] as Map<String, dynamic>;

      final db = await _database;
      final batch = db.batch();

      // templates
      batch.delete('templates');
      final templates = content['templates'] as List<dynamic>? ?? [];
      for (final item in templates) {
        final t = TrainingTemplate.fromJson(item as Map<String, dynamic>);
        batch.insert('templates', {'id': t.id, 'data': jsonEncode(t.toJson())},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // folders
      batch.delete('folders');
      final folders = content['folders'] as List<dynamic>? ?? [];
      for (final f in folders) {
        batch.insert('folders', {'name': f.toString()});
      }

      // draft
      batch.delete('draft');
      final draft = content['draft'];
      if (draft != null) {
        batch.insert('draft', {'id': 1, 'data': jsonEncode(draft)},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // modelConfig
      batch.delete('model_config');
      final modelConfig = content['modelConfig'];
      if (modelConfig != null) {
        batch.insert('model_config', {'id': 1, 'data': jsonEncode(modelConfig)},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // workout sessions (relational)
      batch.delete('workout_sets');
      batch.delete('workout_sessions');
      final av = content['workouts'] as List<dynamic>?; // legacy v1
      if (av != null) {
        for (final item in av) {
          final w = WorkoutSession.fromJson(item as Map<String, dynamic>);
          batch.insert('workout_sessions', {
            'id': w.id,
            'template_id': w.templateId,
            'template_name': w.templateName,
            'start_time': w.startTime.toIso8601String(),
            'end_time': w.endTime?.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          for (int i = 0; i < w.exercises.length; i++) {
            final e = w.exercises[i];
            for (int j = 0; j < e.sets.length; j++) {
              final s = e.sets[j];
              batch.insert('workout_sets', {
                'session_id': w.id,
                'group_title': e.groupTitle,
                'card_name': e.cardName,
                'exercise_name': e.cardName,
                'is_alternative': e.isAlternative ? 1 : 0,
                'set_index': i * 100 + j,
                'weight_kg': s.weightKg,
                'reps': s.reps,
                'rest_sec': s.restSec,
                'feeling': e.feeling?.name,
                'compensation': e.compensation,
                'notes': e.notes,
                'weight_modified': e.weightModified ? 1 : 0,
                'reps_modified': e.repsModified ? 1 : 0,
                'rest_modified': e.restModified ? 1 : 0,
              });
            }
          }
        }
      }
      final sessions = content['sessions'] as List<dynamic>?;
      if (sessions != null) {
        for (final s in sessions) {
          batch.insert('workout_sessions', s as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      final sets = content['sets'] as List<dynamic>?;
      if (sets != null) {
        for (final s in sets) {
          final map = s as Map<String, dynamic>;
          batch.insert('workout_sets', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('[restoreFromJsonFile] ERROR: $e');
      return false;
    }
  }

  /// 返回可读的备份目录大小
  Future<String> get backupSizeText async {
    try {
      final backupDir = await _backupDirPath;
      final dir = Directory(backupDir);
      if (!dir.existsSync()) return '0 B';
      int total = 0;
      for (final f in dir.listSync()) {
        if (f is File) total += await f.length();
      }
      if (total < 1024) return '$total B';
      if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(1)} KB';
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return 'N/A';
    }
  }

  // ─── 从 SharedPreferences 迁移 ───

  Future<void> _migrateFromPrefs(Directory dir) async {
    final flagFile = File('${dir.path}/.migrated_v2');
    if (flagFile.existsSync()) return;

    // 检查是否已有 SQLite 数据（来自旧版文件存储的迁移标记）
    final oldFlag = File('${dir.path}/.migrated_v1');
    if (oldFlag.existsSync()) {
      // 已迁移到文件，无需再从 SharedPreferences 迁移
      await flagFile.writeAsString('1');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    var hasData = false;

    // 直接打开数据库，避免与 _initDb 递归调用
    final path = '${dir.path}/$_dbName';
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );

    // templates
    final tRaw = prefs.getString('bmb_templates');
    if (tRaw != null && tRaw.isNotEmpty) {
      final list = jsonDecode(tRaw) as List<dynamic>;
      for (final item in list) {
        final t = TrainingTemplate.fromJson(item as Map<String, dynamic>);
        await db.insert('templates', {'id': t.id, 'data': jsonEncode(t.toJson())},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      hasData = true;
    }

    // folders
    final fRaw = prefs.getStringList('bmb_template_folders');
    if (fRaw != null && fRaw.isNotEmpty) {
      for (final f in fRaw.toSet()) {
        await db.insert('folders', {'name': f},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      hasData = true;
    }

    // draft
    final dRaw = prefs.getString('bmb_template_draft');
    if (dRaw != null && dRaw.isNotEmpty) {
      await db.insert('draft', {'id': 1, 'data': dRaw},
          conflictAlgorithm: ConflictAlgorithm.replace);
      hasData = true;
    }

    // model config
    final mRaw = prefs.getString('bmb_model_config');
    if (mRaw != null && mRaw.isNotEmpty) {
      await db.insert('model_config', {'id': 1, 'data': mRaw},
          conflictAlgorithm: ConflictAlgorithm.replace);
      hasData = true;
    }

    // workouts
    final wRaw = prefs.getString('bmb_workouts');
    if (wRaw != null && wRaw.isNotEmpty) {
      final list = jsonDecode(wRaw) as List<dynamic>;
      for (final item in list) {
        final w = WorkoutSession.fromJson(item as Map<String, dynamic>);
        await db.insert('workouts', {'id': w.id, 'data': jsonEncode(w.toJson())},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      hasData = true;
    }

    if (hasData) {
      await prefs.remove('bmb_templates');
      await prefs.remove('bmb_template_folders');
      await prefs.remove('bmb_template_draft');
      await prefs.remove('bmb_model_config');
      await prefs.remove('bmb_workouts');
    }

    await db.close();
    await flagFile.writeAsString('1');
  }

  /// DB v1 → v2: migrate workouts blob to workout_sessions + workout_sets
  Future<void> _migrateDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ensure all required tables exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS active_workout (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          data TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workout_sessions (
          id TEXT PRIMARY KEY,
          template_id TEXT,
          template_name TEXT,
          start_time TEXT NOT NULL,
          end_time TEXT,
          ai_summary TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workout_sets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          group_title TEXT NOT NULL,
          card_name TEXT NOT NULL,
          exercise_name TEXT NOT NULL,
          is_alternative INTEGER NOT NULL DEFAULT 0,
          set_index INTEGER NOT NULL,
          weight_kg REAL NOT NULL,
          reps INTEGER NOT NULL,
          rest_sec INTEGER NOT NULL,
          feeling TEXT,
          compensation TEXT,
          notes TEXT,
          weight_modified INTEGER NOT NULL DEFAULT 0,
          reps_modified INTEGER NOT NULL DEFAULT 0,
          rest_modified INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_workout_sets_session ON workout_sets(session_id)');

      // migrate old data
      final oldRows = await db.query('workouts');
      for (final row in oldRows) {
        try {
          final w = WorkoutSession.fromJson(
              jsonDecode(row['data'] as String) as Map<String, dynamic>);
          await db.insert('workout_sessions', {
            'id': w.id,
            'template_id': w.templateId,
            'template_name': w.templateName,
            'start_time': w.startTime.toIso8601String(),
            'end_time': w.endTime?.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          for (int i = 0; i < w.exercises.length; i++) {
            final e = w.exercises[i];
            for (int j = 0; j < e.sets.length; j++) {
              final s = e.sets[j];
              await db.insert('workout_sets', {
                'session_id': w.id,
                'group_title': e.groupTitle,
                'card_name': e.cardName,
                'exercise_name': e.cardName,
                'is_alternative': e.isAlternative ? 1 : 0,
                'set_index': i * 100 + j,
                'weight_kg': s.weightKg,
                'reps': s.reps,
                'rest_sec': s.restSec,
                'feeling': e.feeling?.name,
                'compensation': e.compensation,
                'notes': e.notes,
                'weight_modified': e.weightModified ? 1 : 0,
                'reps_modified': e.repsModified ? 1 : 0,
                'rest_modified': e.restModified ? 1 : 0,
              });
            }
          }
        } catch (e) {
          debugPrint('[migrate v1->v2] skip row: $e');
        }
      }

      // drop old table
      await db.execute('DROP TABLE IF EXISTS workouts');
    }

    // 兼容旧 DB：尝试添加 ai_summary 列（若已存在则静默失败）
    try {
      await db.execute('ALTER TABLE workout_sessions ADD COLUMN ai_summary TEXT');
    } catch (_) {}
  }
}

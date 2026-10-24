import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/local_id.dart';
import '../data/repositories/field_repository.dart';
import '../models/da_batch_import.dart';

/// Pending gallery files are copied out of the picker's temporary cache.
class DaBatchImportStore {
  DaBatchImportStore(
    this.database, {
    Future<Directory> Function()? rootDirectory,
  }) : _root = rootDirectory ?? getApplicationDocumentsDirectory;
  final AppDatabase database;
  final Future<Directory> Function() _root;
  String _key(String assessment, String block) =>
      'da_batch_import_v1_${assessment}_$block';
  Future<DaBatchImportDraft?> load(String assessment, String block) async {
    final json = await FieldRepository(
      database,
    ).readPreferenceValue(_key(assessment, block));
    if (json == null) return null;
    final draft = DaBatchImportDraft.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
    if (draft.assessmentId != assessment || draft.blockId != block)
      throw StateError('Import belongs to another sample.');
    return draft;
  }

  Future<void> save(DaBatchImportDraft draft) =>
      FieldRepository(database).savePreferenceValue(
        _key(draft.assessmentId, draft.blockId),
        jsonEncode(draft.toJson()),
      );
  Future<DaBatchImportDraft> create({
    required String assessmentId,
    required String blockId,
    required List<int> plantNumbers,
    required List<String> paths,
  }) async {
    if (paths.isEmpty ||
        plantNumbers.isEmpty ||
        paths.length > plantNumbers.length * 3) {
      throw StateError('Choose up to ${plantNumbers.length * 3} photos.');
    }
    final id = LocalId.generate();
    final directory = Directory(
      '${(await _root()).path}/WormWiseBatchImports/$id',
    );
    await directory.create(recursive: true);
    final photos = <DaBatchPhoto>[];
    final seen = <String>{};
    for (final path in paths) {
      final source = File(path);
      final checksum = (await sha256.bind(source.openRead()).first).toString();
      if (!seen.add(checksum)) continue;
      final photoId = LocalId.generate();
      final target = File('${directory.path}/$photoId.image');
      await source.copy(target.path);
      photos.add(
        DaBatchPhoto(id: photoId, path: target.path, checksum: checksum),
      );
      // Persist each copied file; interruption does not discard copied progress.
      final draft = DaBatchImportDraft(
        id: id,
        assessmentId: assessmentId,
        blockId: blockId,
        plantNumbers: List.of(plantNumbers),
        photos: List.of(photos),
        starts: photos.length <= plantNumbers.length
            ? photos.map((p) => p.id).toSet()
            : {photos.first.id},
      );
      await save(draft);
    }
    return (await load(assessmentId, blockId))!;
  }

  Future<void> clear(DaBatchImportDraft draft) async {
    await (database.delete(database.appPreferences)..where(
          (p) =>
              p.preferenceKey.equals(_key(draft.assessmentId, draft.blockId)),
        ))
        .go();
    // Only this draft's generated staging directory is removable. Accepted
    // evidence has already been copied into the separate evidence store.
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(draft.id)) return;
    final base = Directory('${(await _root()).path}/WormWiseBatchImports');
    final directory = Directory('${base.path}/${draft.id}');
    if (!await directory.exists()) return;
    final root = (await base.resolveSymbolicLinks()).toLowerCase();
    final target = (await directory.resolveSymbolicLinks()).toLowerCase();
    if (!target.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Invalid import staging directory.');
    }
    await directory.delete(recursive: true);
  }
}

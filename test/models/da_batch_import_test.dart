import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/models/da_batch_import.dart';
import 'package:wormwise/services/da_batch_import_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DaBatchImportDraft draft(int count) => DaBatchImportDraft(
    id: 'draft',
    assessmentId: 'assessment',
    blockId: 'block',
    plantNumbers: [1, 2, 3],
    photos: [
      for (var i = 0; i < count; i++)
        DaBatchPhoto(id: 'p$i', path: 'photo$i', checksum: '$i'),
    ],
    starts: {'p0'},
  );
  test(
    'mixed overview/closer photos group by boundaries, switch overview and move',
    () {
      final d = draft(6);
      expect(d.valid, false);
      d.toggleStart('p3');
      d.toggleStart('p4');
      expect(d.groups.map((g) => g.length), [3, 1, 2]);
      expect(d.valid, true);
      d.confirmed = true;
      d.makeOverview('p2');
      expect(d.groups.first.map((p) => p.id), ['p2', 'p0', 'p1']);
      expect(d.confirmed, false);
      d.move('p1', 1);
      expect(d.groups.map((g) => g.length), [2, 2, 2]);
      d.move('p4', 1);
      expect(d.groups.map((g) => g.length), [2, 3, 1]);
      expect(() => d.move('p0', 1), throwsStateError);
      expect(d.groups.map((g) => g.length), [2, 3, 1]);
      final restored = DaBatchImportDraft.fromJson(d.toJson());
      expect(
        restored.groups.map((g) => g.map((p) => p.id).join(',')),
        d.groups.map((g) => g.map((p) => p.id).join(',')),
      );
      restored.locked = true;
      expect(() => restored.toggleStart('p1'), throwsStateError);
      expect(() => restored.makeOverview('p1'), throwsStateError);
    },
  );
  test(
    'one photo proposals still require confirmation and saved views count one plant',
    () {
      final d = draft(3)..onePerPlant();
      expect(d.valid, true);
      expect(d.confirmed, false);
      expect(d.complete, false);
      d.saved.addAll(d.photos.map((p) => p.id));
      expect(d.complete, false);
      d.screened.addAll([1, 2, 3]);
      expect(d.complete, true);
      d.remove('p1');
      expect(d.groups.length, 2);
    },
  );
  test(
    'capture-sequence shortcuts respect the plant limit and reset confirmation',
    () {
      final d = draft(6);
      expect(() => d.groupByCount(1), throwsStateError);
      d.groupByCount(2);
      expect(d.groups.map((g) => g.length), [2, 2, 2]);
      d.confirmed = true;
      d.groupByCount(3);
      expect(d.groups.map((g) => g.length), [3, 3]);
      expect(d.confirmed, false);
      expect(() => d.groupByCount(4), throwsStateError);
      d.locked = true;
      expect(() => d.groupByCount(2), throwsStateError);
    },
  );
  test(
    'copies survive picker cache removal, deduplicate and isolate block drafts',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('da_batch_store_');
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final a = File('${dir.path}/a.jpg'), b = File('${dir.path}/b.jpg');
      await a.writeAsBytes([1, 2, 3]);
      await b.writeAsBytes([4, 5, 6]);
      final store = DaBatchImportStore(db, rootDirectory: () async => dir);
      final d = await store.create(
        assessmentId: 'assessment',
        blockId: 'b1',
        plantNumbers: [1, 2],
        paths: [a.path, b.path, a.path],
      );
      expect(d.photos.length, 2);
      expect(d.confirmed, false);
      await a.delete();
      await b.delete();
      final saved = await store.load('assessment', 'b1');
      expect(await File(saved!.photos.first.path).readAsBytes(), [1, 2, 3]);
      expect(await store.load('assessment', 'b2'), null);
      saved.locked = true;
      saved.saved.add(saved.photos.first.id);
      await store.save(saved);
      expect((await store.load('assessment', 'b1'))!.saved, saved.saved);
      await store.clear(saved);
      expect(await store.load('assessment', 'b1'), null);
      expect(await File(saved.photos.first.path).exists(), false);
      expect(await dir.exists(), true);
    },
  );
}

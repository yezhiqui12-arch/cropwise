/// A gallery batch is a draft until plant groups are explicitly reviewed.
class DaBatchPhoto {
  const DaBatchPhoto({
    required this.id,
    required this.path,
    required this.checksum,
  });
  final String id, path, checksum;
  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'checksum': checksum,
  };
  factory DaBatchPhoto.fromJson(Map<String, dynamic> j) => DaBatchPhoto(
    id: j['id'] as String,
    path: j['path'] as String,
    checksum: j['checksum'] as String,
  );
}

class DaBatchImportDraft {
  DaBatchImportDraft({
    required this.id,
    required this.assessmentId,
    required this.blockId,
    required this.plantNumbers,
    required this.photos,
    required this.starts,
    this.confirmed = false,
    this.locked = false,
    Set<String>? saved,
    Set<int>? screened,
  }) : saved = saved ?? {},
       screened = screened ?? {};
  final String id, assessmentId, blockId;
  final List<int> plantNumbers;
  final List<DaBatchPhoto> photos;
  final Set<String> starts;
  final Set<String> saved;
  final Set<int> screened;
  bool confirmed, locked;
  List<List<DaBatchPhoto>> get groups {
    final result = <List<DaBatchPhoto>>[];
    for (final photo in photos) {
      if (result.isEmpty || starts.contains(photo.id)) result.add([]);
      result.last.add(photo);
    }
    return result;
  }

  bool get valid =>
      photos.isNotEmpty &&
      groups.length <= plantNumbers.length &&
      groups.every((g) => g.isNotEmpty && g.length <= 3) &&
      photos.map((p) => p.id).toSet().length == photos.length &&
      plantNumbers.toSet().length == plantNumbers.length &&
      plantNumbers.every((n) => n >= 1 && n <= 20);
  bool get complete =>
      valid &&
      photos.every((p) => saved.contains(p.id)) &&
      groups.asMap().keys.every((i) => screened.contains(plantNumbers[i]));
  void toggleStart(String photoId) {
    _editable();
    if (photos.isEmpty || photos.first.id == photoId) return;
    if (!photos.any((p) => p.id == photoId))
      throw ArgumentError('Unknown photo');
    starts.contains(photoId) ? starts.remove(photoId) : starts.add(photoId);
    confirmed = false;
  }

  void makeOverview(String photoId) {
    _editable();
    final current = groups;
    final group = current.firstWhere((g) => g.any((p) => p.id == photoId));
    final photo = group.firstWhere((p) => p.id == photoId);
    group.remove(photo);
    group.insert(0, photo);
    _replaceGroups(current);
  }

  void move(String photoId, int target) {
    _editable();
    final current = groups;
    if (target < 0 || target >= current.length)
      throw ArgumentError('Unknown plant');
    final source = current.indexWhere((g) => g.any((p) => p.id == photoId));
    if (source < 0) throw ArgumentError('Unknown photo');
    if (source == target) return;
    if (current[target].length >= 3)
      throw StateError('Each plant allows 3 photos.');
    final photo = current[source].firstWhere((p) => p.id == photoId);
    current[source].remove(photo);
    current[target].add(photo);
    _replaceGroups(current.where((g) => g.isNotEmpty).toList());
  }

  void remove(String photoId) {
    _editable();
    final current = groups;
    for (final group in current) {
      group.removeWhere((p) => p.id == photoId);
    }
    _replaceGroups(current.where((g) => g.isNotEmpty).toList());
  }

  void onePerPlant() {
    groupByCount(1);
  }

  void groupByCount(int count) {
    _editable();
    if (count < 1 ||
        count > 3 ||
        (photos.length / count).ceil() > plantNumbers.length) {
      throw StateError(
        'Choose groups of 1–3 photos within the available plants.',
      );
    }
    starts
      ..clear()
      ..addAll([for (var i = 0; i < photos.length; i += count) photos[i].id]);
    confirmed = false;
  }

  void _replaceGroups(List<List<DaBatchPhoto>> current) {
    photos
      ..clear()
      ..addAll(current.expand((g) => g));
    starts
      ..clear()
      ..addAll(current.map((g) => g.first.id));
    confirmed = false;
  }

  void _editable() {
    if (locked) throw StateError('Saved groups cannot be changed.');
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'assessment_id': assessmentId,
    'block_id': blockId,
    'plant_numbers': plantNumbers,
    'photos': photos.map((p) => p.toJson()).toList(),
    'starts': starts.toList(),
    'confirmed': confirmed,
    'locked': locked,
    'saved': saved.toList(),
    'screened': screened.toList(),
  };
  factory DaBatchImportDraft.fromJson(Map<String, dynamic> j) =>
      DaBatchImportDraft(
        id: j['id'] as String,
        assessmentId: j['assessment_id'] as String,
        blockId: j['block_id'] as String,
        plantNumbers: List<int>.from(j['plant_numbers'] as List),
        photos: (j['photos'] as List)
            .map(
              (p) => DaBatchPhoto.fromJson(Map<String, dynamic>.from(p as Map)),
            )
            .toList(),
        starts: Set<String>.from(j['starts'] as List),
        confirmed: j['confirmed'] == true,
        locked: j['locked'] == true,
        saved: Set<String>.from(j['saved'] as List? ?? []),
        screened: Set<int>.from(j['screened'] as List? ?? []),
      );
}

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Profile photos stay on this device and are scoped to the signed-in user.
class ProfileAvatarStore {
  const ProfileAvatarStore();

  Future<File> fileFor(String? userId) async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}profile_avatars',
    );
    await folder.create(recursive: true);
    final safeId = (userId ?? 'guest').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    return File('${folder.path}${Platform.pathSeparator}$safeId.jpg');
  }

  Future<File?> pickAndSave(String? userId, ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (picked == null) return null;
    final target = await fileFor(userId);
    await target.writeAsBytes(await picked.readAsBytes(), flush: true);
    return target;
  }

  Future<void> remove(String? userId) async {
    final target = await fileFor(userId);
    if (await target.exists()) await target.delete();
  }
}

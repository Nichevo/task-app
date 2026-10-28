import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'input_parse.dart';
import 'native.dart';
import 'store.dart';
import 'widgets/add_dialogs.dart';

/// Takes or picks a photo of a written list, reads the lines on the phone and offers each
/// one as a task.
Future<void> importPhoto(BuildContext context, AppStore store) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
    if (file == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('Reading the photo…'), duration: Duration(seconds: 2)));
    final lines = splitLines((await Native.recognizeText(file.path)).join('\n'));
    if (!context.mounted) return;
    if (lines.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No writing found in that photo.')));
      return;
    }
    await showAddManyDialog(context, store, lines, title: 'Found ${lines.length} line${lines.length == 1 ? '' : 's'}');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not read the photo: $e')));
  }
}

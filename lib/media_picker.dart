import 'package:file_picker/file_picker.dart';

import 'tv/model.dart';

/// Telefondan video, musiqa yoki rasm tanlash.
/// [gallery] — Galereya (video va rasm), aks holda Fayllar (musiqa ham).
Future<List<MediaItem>> pickMedia({required bool gallery}) async {
  final res = await FilePicker.pickFiles(
    type: gallery ? FileType.media : FileType.any,
    allowMultiple: true,
  );
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.path case final path?)
        if (MediaItem.kindForName(f.name) case final kind?)
          MediaItem(title: _title(f.name), source: path, kind: kind),
  ];
}

String _title(String name) {
  final dot = name.lastIndexOf('.');
  return (dot > 0 ? name.substring(0, dot) : name).replaceAll('_', ' ');
}

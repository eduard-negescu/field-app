import 'package:firebase_storage/firebase_storage.dart';

/// Step 11, on the web: the photo is a data: URI (week 3).
Future<void> putPhoto(Reference ref, String localUri, SettableMetadata meta) =>
    ref.putString(localUri, format: PutStringFormat.dataUrl, metadata: meta);

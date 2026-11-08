import 'dart:io' show File;

import 'package:firebase_storage/firebase_storage.dart';

/// Step 11, on Android/iOS: the photo is a file on the phone.
Future<void> putPhoto(Reference ref, String localUri, SettableMetadata meta) =>
    ref.putFile(File(localUri), meta);

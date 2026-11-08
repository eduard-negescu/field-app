import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'contract/contract.dart';
import 'db/database.dart';
import 'photo_upload.dart';
import 'providers.dart';
import 'repositories.dart';

/// Server state: my pins as the cloud has them, live (one Firestore listener).
/// The banner watches it; SyncScope copies every new list into SQLite.
final myPinsProvider = StreamProvider<List<Entrance>>(
  (ref) => ref.watch(pinsRepositoryProvider).watchMine(ref.watch(uidProvider)),
);

final outboxProvider = StreamProvider(
  (ref) => ref.watch(databaseProvider).watchOutbox(),
);

var _pushing = false;

/// The outbox push: every unsent survey goes up as surveys/{entranceId} with
/// set(). The id is the survey's own, so a second push (the app was killed
/// before it heard "ok") overwrites the same document: idempotent. Offline,
/// set() waits until the network is back; SQLite keeps the survey meanwhile.
Future<void> pushSurveys(WidgetRef ref) async {
  if (_pushing) return; // one push at a time
  _pushing = true;
  final db = ref.read(databaseProvider);
  final surveys = ref.read(surveysRepositoryProvider);
  final uid = ref.read(uidProvider);
  try {
    for (final e in await db.outbox()) {
      try {
        await surveys.push(surveyDoc(e, uid));
        await db.markSent(e.id, e.updatedAt, null);
      } on FirebaseException catch (err) {
        // permission-denied: the rules refused it (the pin is no longer mine).
        await db.markSent(e.id, e.updatedAt, err.code);
      }
    }
    // Step 11 (optional): the photos, when the project has Storage.
    if (const bool.fromEnvironment('UPLOAD_PHOTOS')) await _pushPhotos(db, uid);
  } finally {
    _pushing = false;
  }
}

/// Every photo not uploaded yet goes to photos/{uid}/{entranceId}/{photoId}.jpg.
Future<void> _pushPhotos(AppDatabase db, String uid) async {
  for (final p in await db.photosToUpload()) {
    final file = FirebaseStorage.instance.ref('photos/$uid/${p.entranceId}/${p.id}.jpg');
    final meta = SettableMetadata(contentType: 'image/jpeg');
    try {
      await putPhoto(file, p.localUri, meta);
      await db.markPhoto(p.id, remoteUrl: await file.getDownloadURL());
    } on FirebaseException catch (err) {
      await db.markPhoto(p.id, error: err.code);
    }
  }
}

/// Wraps the signed-in app: while it is on screen, the pull runs. Signing out
/// removes it, and Riverpod stops the listener nobody watches any more.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> {
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<List<ConnectivityResult>> _network;

  @override
  void initState() {
    super.initState();
    // The push, at three moments: now, back in the foreground, and when the
    // network comes back. (And on "Sync now", and after a submit.)
    pushSurveys(ref);
    _lifecycle = AppLifecycleListener(onResume: () => pushSurveys(ref));
    _network = Connectivity().onConnectivityChanged.listen((links) {
      if (!links.contains(ConnectivityResult.none)) pushSurveys(ref);
    });
    // The pull: every snapshot of my pins goes to SQLite, the truth on the
    // phone. listenManual keeps the listener alive while this widget lives.
    ref.listenManual(myPinsProvider, (_, next) {
      final pins = next.value;
      if (pins != null) ref.read(databaseProvider).savePins(pins);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _network.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

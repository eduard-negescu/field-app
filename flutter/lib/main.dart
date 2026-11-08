import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth.dart';
import 'db/database.dart';
import 'firebase_options.dart'; // written by flutterfire configure (git-ignored)
import 'providers.dart';
import 'screens/entrance_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/map_screen.dart';
import 'screens/route_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/survey_screen.dart';
import 'session.dart';
import 'store.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything that talks to Firebase: your project's options, per platform.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Step 11, no card: the Local Emulator Suite on your PC instead of Google's
  // servers. flutter run --dart-define=USE_EMULATORS=true. The browser finds
  // them on localhost; the Android emulator reaches your PC as 10.0.2.2; a
  // phone needs your PC's LAN address (--dart-define=EMULATOR_HOST=…).
  if (const bool.fromEnvironment('USE_EMULATORS')) {
    const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
    final h = kIsWeb ? 'localhost' : host;
    await FirebaseAuth.instance.useAuthEmulator(h, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(h, 8080);
    await FirebaseStorage.instance.useStorageEmulator(h, 9199);
  }
  final fixtures = await Fixtures.load();
  // The app's truth: SQLite. The buildings come from the fixtures once; the
  // entrances, from the cloud (sync.dart).
  final db = AppDatabase();
  await db.seedIfEmpty(fixtures.buildings);
  _startAt = await lastTab(); // reopen on the tab the app was closed on
  runApp(ProviderScope(
    // Hand the two things main() opened to every provider that asks for them.
    overrides: [
      fixturesProvider.overrideWithValue(fixtures),
      databaseProvider.overrideWithValue(db),
    ],
    child: const FieldApp(),
  ));
}

const _tabs = ['/map', '/route', '/inbox'];
var _startAt = _tabs.first;

// A top-level final is created on first use (in FieldApp), after main() has
// read _startAt.
final _router = GoRouter(
  initialLocation: _startAt,
  routes: [
    // The three tabs: each branch keeps its own navigation stack.
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => TabsShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/route', builder: (context, state) => const RouteScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/inbox',
            builder: (context, state) => const InboxScreen(),
            routes: [
              GoRoute(
                path: 'conversations/:id',
                builder: (context, state) =>
                    ConversationScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
      ],
    ),
    // Outside the shell: these cover the tab bar, like a stack screen.
    GoRoute(
      path: '/entrances/:id',
      builder: (context, state) =>
          EntranceScreen(id: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'survey',
          builder: (context, state) =>
              SurveyScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

const _seed = Color(0xFFC2410C);
final _light = ThemeData(colorSchemeSeed: _seed, brightness: Brightness.light);
final _dark = ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark);

/// The auth-state gate: no user, no app. Signing in or out rebuilds this.
class FieldApp extends ConsumerWidget {
  const FieldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    if (user.value == null) {
      return MaterialApp(
        title: 'Field app',
        theme: _light,
        darkTheme: _dark,
        home: user.isLoading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : const SignInScreen(),
      );
    }
    // The sync runs while a worker is signed in (SyncScope, sync.dart).
    return SyncScope(
      child: MaterialApp.router(
        title: 'Field app',
        routerConfig: _router,
        theme: _light,
        darkTheme: _dark,
        themeMode: ThemeMode.system, // follow the phone's setting
      ),
    );
  }
}

class TabsShell extends ConsumerWidget {
  const TabsShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(fixturesProvider);
    final unread = f.messages
        .where((m) => m.authorId != f.me && !m.readAt.containsKey(f.me))
        .where((m) => f.conversations
            .any((c) => c.id == m.conversationId && c.participantIds.contains(f.me)))
        .length;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Tapping the current tab again goes back to its first screen.
        onDestinationSelected: (i) {
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
          saveLastTab(_tabs[i]);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          const NavigationDestination(icon: Icon(Icons.list_alt), label: 'My route'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.mail_outline),
            ),
            label: 'Inbox',
          ),
        ],
      ),
    );
  }
}

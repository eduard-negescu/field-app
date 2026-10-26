import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/entrance_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/map_screen.dart';
import 'screens/route_screen.dart';
import 'screens/survey_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FieldStore(await Fixtures.load());
  runApp(StoreScope(store: store, child: const FieldApp()));
}

final _router = GoRouter(
  initialLocation: '/map',
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

class FieldApp extends StatelessWidget {
  const FieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFC2410C);
    return MaterialApp.router(
      title: 'Field app',
      routerConfig: _router,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      themeMode: ThemeMode.system, // follow the phone's setting
    );
  }
}

class TabsShell extends StatelessWidget {
  const TabsShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final f = store.fixtures;
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
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
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

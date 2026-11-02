import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../contract/contract.dart';
import '../providers.dart';
import 'status_chip.dart';

class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(fixturesProvider);
    final byId = {for (final e in ref.watch(entrancesProvider).value ?? const <Entrance>[]) e.id: e};
    final route = f.routes.firstWhere((r) => r.workerId == f.me);
    final stops = f.stops.where((s) => s.routeId == route.id).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      appBar: AppBar(title: Text('${route.name} · ${route.date}')),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: stops.length,
        itemBuilder: (context, i) {
          final e = byId[stops[i].entranceId];
          if (e == null) return const SizedBox.shrink(); // SQLite not read yet
          return Card(
            child: ListTile(
              leading: Text('${stops[i].order}',
                  style: Theme.of(context).textTheme.titleLarge),
              title: Text('${e.street} ${e.number}'),
              subtitle: Text(e.entranceName),
              trailing: StatusChip(status: e.surveyStatus),
              onTap: () => context.push('/entrances/${e.id}'),
            ),
          );
        },
      ),
    );
  }
}

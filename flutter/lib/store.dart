import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
// The contract has its own Route (an admin's list of stops); hide Flutter's.
import 'package:flutter/widgets.dart' hide Route;

import 'contract/contract.dart';

/// The fixtures, read once from the assets and checked against the contract.
class Fixtures {
  Fixtures(this.users, this.buildings, this.entrances, this.routes,
      this.stops, this.conversations, this.messages);

  final List<User> users;
  final List<Building> buildings;
  final List<Entrance> entrances;
  final List<Route> routes;
  final List<RouteStop> stops;
  final List<Conversation> conversations;
  final List<Message> messages;

  /// Who is "signed in" until week 4: the worker of the first route.
  String get me => routes.first.workerId;

  static Future<Fixtures> load() async {
    Future<List<Map<String, dynamic>>> read(String name) async =>
        (jsonDecode(await rootBundle.loadString('assets/fixtures/$name.json'))
                as List)
            .cast<Map<String, dynamic>>();

    T check<T>(T row, List<String> Function(T) validate) {
      final errors = validate(row);
      if (errors.isNotEmpty) throw FormatException(errors.join('; '));
      return row;
    }

    final routesJson = await read('routes');
    return Fixtures(
      [for (final j in await read('users')) check(User.fromJson(j), validateUser)],
      [for (final j in await read('buildings')) check(Building.fromJson(j), validateBuilding)],
      [for (final j in await read('entrances')) check(Entrance.fromJson(j), validateEntrance)],
      [for (final j in routesJson) check(Route.fromJson(j), validateRoute)],
      [
        for (final r in routesJson)
          for (final s in (r['stops'] as List).cast<Map<String, dynamic>>())
            check(RouteStop.fromJson(s), validateRouteStop),
      ],
      [for (final j in await read('conversations')) check(Conversation.fromJson(j), validateConversation)],
      [for (final j in await read('messages')) check(Message.fromJson(j), validateMessage)],
    );
  }
}

/// The one in-memory store: a ChangeNotifier the whole app listens to.
class FieldStore extends ChangeNotifier {
  FieldStore(this.fixtures) : _entrances = List.of(fixtures.entrances);

  final Fixtures fixtures;
  List<Entrance> _entrances;

  List<Entrance> get entrances => _entrances;
  Entrance? entrance(String id) =>
      _entrances.where((e) => e.id == id).firstOrNull;

  void submitSurvey(Entrance surveyed) {
    final now = DateTime.now().toUtc().toIso8601String();
    _entrances = [
      for (final e in _entrances)
        e.id == surveyed.id
            ? surveyed.copyWith(
                surveyStatus: SurveyStatus.submitted,
                surveyedBy: fixtures.me,
                surveyedAt: now,
                updatedAt: now,
              )
            : e,
    ];
    notifyListeners();
  }
}

/// Puts the store in the widget tree; widgets that read it rebuild on change.
class StoreScope extends InheritedNotifier<FieldStore> {
  const StoreScope({super.key, required FieldStore store, required super.child})
      : super(notifier: store);

  static FieldStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

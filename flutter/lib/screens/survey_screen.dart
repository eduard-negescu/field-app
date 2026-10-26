import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../contract/contract.dart';
import '../store.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.id});

  final String id;

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Entrance _entrance;
  late bool _coordsConfirmed, _addressConfirmed, _groundFloorCommercial;
  late final Map<String, TextEditingController> _text;
  Map<String, String> _ruleErrors = {};

  @override
  void initState() {
    super.initState();
    _text = {};
  }

  void _init(Entrance e) {
    _entrance = e;
    _coordsConfirmed = e.coordsConfirmed;
    _addressConfirmed = e.addressConfirmed;
    _groundFloorCommercial = e.groundFloorCommercial ?? false;
    String s(Object? v) => v == null ? '' : '$v';
    _text.addAll({
      'correctedLat': TextEditingController(text: s(e.correctedLat)),
      'correctedLng': TextEditingController(text: s(e.correctedLng)),
      'street': TextEditingController(text: e.street),
      'number': TextEditingController(text: e.number),
      'entranceName': TextEditingController(text: e.entranceName),
      'stories': TextEditingController(text: s(e.stories)),
      'flats': TextEditingController(text: s(e.flats)),
      'elevators': TextEditingController(text: s(e.elevators)),
      'yearBuilt': TextEditingController(text: s(e.yearBuilt)),
      'comment': TextEditingController(text: e.comment ?? ''),
    });
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(String key) => int.tryParse(_text[key]!.text.trim());
  double? _double(String key) => double.tryParse(_text[key]!.text.trim());

  /// The form's values as an entrance, so the contract can check the rules
  /// that span several fields.
  Entrance _candidate() => Entrance(
        id: _entrance.id,
        createdAt: _entrance.createdAt,
        updatedAt: _entrance.updatedAt,
        buildingId: _entrance.buildingId,
        lat: _entrance.lat,
        lng: _entrance.lng,
        street: _text['street']!.text.trim(),
        number: _text['number']!.text.trim(),
        entranceName: _text['entranceName']!.text.trim(),
        coordsConfirmed: _coordsConfirmed,
        correctedLat: _coordsConfirmed ? null : _double('correctedLat'),
        correctedLng: _coordsConfirmed ? null : _double('correctedLng'),
        addressConfirmed: _addressConfirmed,
        stories: _int('stories'),
        flats: _int('flats'),
        elevators: _int('elevators'),
        yearBuilt: _int('yearBuilt'),
        groundFloorCommercial: _groundFloorCommercial,
        comment: _text['comment']!.text.trim().isEmpty ? null : _text['comment']!.text.trim(),
        surveyStatus: _entrance.surveyStatus,
        surveyedBy: _entrance.surveyedBy,
        surveyedAt: _entrance.surveyedAt,
      );

  void _submit() {
    final fieldsOk = _formKey.currentState!.validate();
    final candidate = _candidate();
    // validateEntranceSurvey returns "field: message" strings.
    final rules = <String, String>{
      for (final err in validateEntranceSurvey(candidate))
        err.split(':').first: err.split(': ').skip(1).join(': '),
    };
    setState(() => _ruleErrors = rules);
    if (!fieldsOk || rules.isNotEmpty) return;
    StoreScope.of(context).submitSurvey(candidate);
    context.pop();
  }

  // A text field whose validator is the contract's.
  Widget _field(String key, String label, String? Function(String?) validator,
          {TextInputType? keyboard}) =>
      TextFormField(
        controller: _text[key],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: keyboard,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
      );

  String? Function(String?) _intRule(String? Function(int?) rule) =>
      (s) => (s ?? '').trim().isNotEmpty && int.tryParse(s!.trim()) == null
          ? 'A whole number'
          : rule(int.tryParse((s ?? '').trim()));

  String? Function(String?) _coordRule(String? Function(num?) rule) =>
      (s) => (s ?? '').trim().isEmpty ? null : rule(double.tryParse(s!.trim()) ?? double.nan);

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) {
      final e = StoreScope.of(context).entrance(widget.id);
      if (e == null) return const Scaffold(body: Center(child: Text('No such entrance.')));
      _init(e);
    }
    const gap = SizedBox(height: 14);
    const number = TextInputType.number;
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    return Scaffold(
      appBar: AppBar(title: const Text('Survey')),
      // The body scrolls, so the keyboard never hides the field being typed.
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('The pin is at the door'),
              subtitle: _ruleError('coordsConfirmed'),
              value: _coordsConfirmed,
              onChanged: (v) => setState(() => _coordsConfirmed = v),
            ),
            if (!_coordsConfirmed) ...[
              _field('correctedLat', 'Corrected latitude', _coordRule(validateLat), keyboard: decimal),
              gap,
              _field('correctedLng', 'Corrected longitude', _coordRule(validateLng), keyboard: decimal),
              if (_ruleErrors['correctedLng'] != null) _ruleError('correctedLng')!,
              gap,
            ],
            _field('street', 'Street', validateStreet),
            gap,
            _field('number', 'Number', validateStreetNumber),
            gap,
            _field('entranceName', 'Entrance', validateEntranceName),
            SwitchListTile(
              title: const Text('I checked the address'),
              subtitle: _ruleError('addressConfirmed'),
              value: _addressConfirmed,
              onChanged: (v) => setState(() => _addressConfirmed = v),
            ),
            _field('stories', 'Stories', _intRule(validateStories), keyboard: number),
            gap,
            _field('flats', 'Flats', _intRule(validateFlats), keyboard: number),
            gap,
            _field('elevators', 'Elevators', _intRule(validateElevators), keyboard: number),
            gap,
            _field('yearBuilt', 'Year built', _intRule(validateYearBuilt), keyboard: number),
            SwitchListTile(
              title: const Text('Shops on the ground floor'),
              value: _groundFloorCommercial,
              onChanged: (v) => setState(() => _groundFloorCommercial = v),
            ),
            TextFormField(
              controller: _text['comment'],
              decoration: const InputDecoration(labelText: 'Comment', border: OutlineInputBorder()),
              maxLines: 4,
              validator: validateFreeText,
            ),
            gap,
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _submit,
              child: const Text('Submit survey'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _ruleError(String key) {
    final message = _ruleErrors[key];
    if (message == null) return null;
    return Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error));
  }
}

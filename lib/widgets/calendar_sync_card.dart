import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class CalendarSyncCard extends StatefulWidget {
  const CalendarSyncCard({super.key});

  @override
  State<CalendarSyncCard> createState() => _CalendarSyncCardState();
}

class _CalendarSyncCardState extends State<CalendarSyncCard> {
  static final _settings = FirebaseFirestore.instance
      .collection('settings')
      .doc('calendar_sync');
  static final _marker = FirebaseFirestore.instance
      .collection('settings')
      .doc('planning_sync');
  static final _connectEndpoint = Uri.parse(
    'https://us-east4-pantry-tracker-4bc45.cloudfunctions.net/calendarAuth?mode=start',
  );

  bool working = false;
  String? localError;

  Future<void> _connect() async {
    await _run(() async {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw StateError('Sign in to connect Calendar.');
      final response = await http.post(
        _connectEndpoint,
        headers: {'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw StateError(
          body['error'] as String? ?? 'Calendar connection failed.',
        );
      }
      final url = Uri.parse(body['authorizationUrl'] as String);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open Google Calendar authorization.');
      }
    });
  }

  Future<void> _requestSync({String action = 'sync'}) => _run(() async {
    final batch = FirebaseFirestore.instance.batch();
    if (action == 'clear') {
      batch.set(_settings, {'enabled': false}, SetOptions(merge: true));
    }
    batch.set(_marker, {
      'generation': FirebaseFirestore.instance.collection('settings').doc().id,
      'action': action,
      'requested_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  });

  Future<void> _setEnabled(bool enabled) => _run(() async {
    final batch = FirebaseFirestore.instance.batch();
    batch.set(_settings, {'enabled': enabled}, SetOptions(merge: true));
    batch.set(_marker, {
      'generation': FirebaseFirestore.instance.collection('settings').doc().id,
      'action': 'sync',
      'requested_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  });

  Future<void> _run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      localError = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => localError = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _settings.snapshots(),
    builder: (context, snapshot) {
      final data = snapshot.data?.data() ?? const <String, dynamic>{};
      final connected = (data['calendar_id'] as String?)?.isNotEmpty ?? false;
      final enabled = data['enabled'] as bool? ?? false;
      final serverError = data['last_error'] as String?;
      final lastSuccess = (data['last_success_at'] as Timestamp?)?.toDate();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected
                              ? (data['calendar_name'] as String? ??
                                    'Pantry Planner')
                              : 'Google Calendar',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          connected
                              ? 'Grocery and recipe-preparation reminders follow this plan.'
                              : 'Connect a dedicated Pantry Planner calendar for grocery and preparation reminders.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (connected)
                    Switch(
                      value: enabled,
                      onChanged: working ? null : _setEnabled,
                    ),
                ],
              ),
              if (localError != null || serverError != null) ...[
                const SizedBox(height: 12),
                Text(
                  localError ?? serverError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (lastSuccess != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Last synchronized ${_dateTimeLabel(lastSuccess)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: working ? null : _connect,
                    icon: working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      connected ? 'Reconnect' : 'Connect Google Calendar',
                    ),
                  ),
                  if (connected) ...[
                    OutlinedButton.icon(
                      onPressed: working
                          ? null
                          : () => _showSettings(context, data),
                      icon: const Icon(Icons.tune),
                      label: const Text('Reminder settings'),
                    ),
                    OutlinedButton.icon(
                      onPressed: working || !enabled ? null : _requestSync,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync now'),
                    ),
                    TextButton.icon(
                      onPressed: working
                          ? null
                          : () => _requestSync(action: 'clear'),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Remove managed events'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _showSettings(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final timeZone = TextEditingController(
      text: data['time_zone'] as String? ?? 'America/New_York',
    );
    final groceryTime = TextEditingController(
      text: data['grocery_time'] as String? ?? '18:00',
    );
    final leadDays = TextEditingController(
      text: '${data['grocery_lead_days'] as num? ?? 1}',
    );
    final groceryReminder = TextEditingController(
      text: '${data['grocery_reminder_minutes'] as num? ?? 0}',
    );
    final prepReminder = TextEditingController(
      text: '${data['prep_reminder_minutes'] as num? ?? 0}',
    );
    final slotData = data['slot_times'] as Map<String, dynamic>? ?? const {};
    final slots = {
      'breakfast': TextEditingController(
        text: slotData['breakfast'] as String? ?? '08:00',
      ),
      'lunch': TextEditingController(
        text: slotData['lunch'] as String? ?? '12:00',
      ),
      'dinner': TextEditingController(
        text: slotData['dinner'] as String? ?? '18:00',
      ),
      'snack': TextEditingController(
        text: slotData['snack'] as String? ?? '15:00',
      ),
    };
    String? error;
    final result = await showDialog<Map<String, Object>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Calendar reminder settings'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: timeZone,
                    decoration: const InputDecoration(
                      labelText: 'IANA time zone',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: leadDays,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Shop days before',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: groceryTime,
                          decoration: const InputDecoration(
                            labelText: 'Grocery time (HH:mm)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: groceryReminder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Grocery popup minutes before',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: prepReminder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prep popup minutes before',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Meal times',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: slots.entries
                        .map(
                          (entry) => SizedBox(
                            width: 115,
                            child: TextField(
                              controller: entry.value,
                              decoration: InputDecoration(labelText: entry.key),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
                final lead = int.tryParse(leadDays.text);
                final groceryMinutes = int.tryParse(groceryReminder.text);
                final prepMinutes = int.tryParse(prepReminder.text);
                if (timeZone.text.trim().isEmpty ||
                    lead == null ||
                    lead < 0 ||
                    lead > 14 ||
                    groceryMinutes == null ||
                    groceryMinutes < 0 ||
                    prepMinutes == null ||
                    prepMinutes < 0 ||
                    !clock.hasMatch(groceryTime.text) ||
                    slots.values.any(
                      (controller) => !clock.hasMatch(controller.text),
                    )) {
                  setDialogState(
                    () => error =
                        'Use a time zone, 0–14 lead days, non-negative reminder minutes, and 24-hour HH:mm times.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  'time_zone': timeZone.text.trim(),
                  'grocery_lead_days': lead,
                  'grocery_time': groceryTime.text,
                  'grocery_reminder_minutes': groceryMinutes,
                  'prep_reminder_minutes': prepMinutes,
                  'slot_times': {
                    for (final entry in slots.entries)
                      entry.key: entry.value.text,
                  },
                });
              },
              child: const Text('Save and sync'),
            ),
          ],
        ),
      ),
    );
    timeZone.dispose();
    groceryTime.dispose();
    leadDays.dispose();
    groceryReminder.dispose();
    prepReminder.dispose();
    for (final controller in slots.values) {
      controller.dispose();
    }
    if (result == null) return;
    await _run(() async {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(_settings, result, SetOptions(merge: true));
      batch.set(_marker, {
        'generation': FirebaseFirestore.instance
            .collection('settings')
            .doc()
            .id,
        'action': 'sync',
        'requested_at': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    });
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} at ${local.hour}:$minute';
  }
}

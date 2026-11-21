import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'gantt.dart' show daysForMinutes;
import 'models.dart';

/// Item 114 G: break a task into steps with AI: Claude (with the owner's own API key) or a model
/// running in Ollama on the home network. Only the task's title, notes, category, due date and
/// existing step names are sent, plus the optional "about me" line from Settings.

/// Which AI to use, and how (in [AppData.helperPrefs]; the Claude key itself is on the device).
extension AiPrefs on AppData {
  /// 'claude' or 'ollama'.
  String get aiProvider => helperPrefs['aiProvider'] as String? ?? 'claude';
  set aiProvider(String v) => helperPrefs['aiProvider'] = v;

  /// Ollama's address, e.g. http://192.168.1.20:11434.
  String get ollamaUrl => helperPrefs['ollamaUrl'] as String? ?? '';
  set ollamaUrl(String v) => helperPrefs['ollamaUrl'] = v.trim();

  String get ollamaModel => helperPrefs['ollamaModel'] as String? ?? 'llama3.1';
  set ollamaModel(String v) => helperPrefs['ollamaModel'] = v.trim();

  /// A line about the owner's work, so the steps fit ("Data analyst in supply chain").
  String get aiAbout => helperPrefs['aiAbout'] as String? ?? '';
  set aiAbout(String v) => helperPrefs['aiAbout'] = v.trim();
}

/// One suggested step.
class AiStep {
  AiStep(this.title, this.minutes, this.after);
  final String title;

  /// Rough length.
  final int minutes;

  /// Places (0-based) of the earlier suggested steps it needs first.
  final List<int> after;
}

/// Something went wrong, in words for the person.
class AiError implements Exception {
  AiError(this.message);
  final String message;
  @override
  String toString() => message;
}

const claudeModel = 'claude-opus-5-5';

const _schema = {
  'type': 'object',
  'properties': {
    'steps': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'minutes': {'type': 'integer'},
          'after': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
        'required': ['title', 'minutes', 'after'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['steps'],
  'additionalProperties': false,
};

String _system(AppData data) => [
      'You help someone plan their work in a personal task app. Break the task they give you into '
          'concrete steps they can tick off, in the order they would do them.',
      'Give 3 to 10 steps. Each title is a short action starting with a verb, under 70 characters, '
          'in plain British English. Leave out steps they already have.',
      'For each step give a realistic length in minutes (whole working days count as 450 minutes) '
          'and, in "after", the 0-based places of earlier steps in your list that must be finished first. '
          'Leave "after" empty when a step can start straight away.',
      if (data.aiAbout.isNotEmpty) 'About the person: ${data.aiAbout}',
    ].join('\n\n');

String _prompt(AppData data, Task t, DateTime now) {
  final fmt = DateFormat('EEEE d MMMM yyyy');
  return [
    'Task: ${t.title}',
    if (t.notes.trim().isNotEmpty) 'Notes:\n${t.notes.trim()}',
    if (data.category(t.categoryId) != null) 'Category: ${data.category(t.categoryId)!.name}',
    if (t.dueAt != null) 'Due: ${fmt.format(t.dueAt!)} (today is ${fmt.format(now)})',
    if (t.steps.isNotEmpty) 'Steps they already have:\n${t.steps.map((s) => '- ${s.title}').join('\n')}',
  ].join('\n\n');
}

List<AiStep> _parse(String text) {
  final Object? j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    throw AiError('The answer wasn\'t in the expected form. Try again.');
  }
  final list = j is Map ? j['steps'] : null;
  if (list is! List || list.isEmpty) throw AiError('No steps came back. Try again, or add a few notes to the task.');
  final out = <AiStep>[];
  for (final (i, x) in list.indexed) {
    if (x is! Map) continue;
    final title = (x['title'] as String? ?? '').trim();
    if (title.isEmpty) continue;
    final minutes = (x['minutes'] as num?)?.round() ?? 30;
    out.add(AiStep(title, minutes.clamp(5, 60 * 24 * 30), [
      for (final a in x['after'] as List? ?? const [])
        if (a is num && a.toInt() >= 0 && a.toInt() < i) a.toInt(),
    ]));
  }
  if (out.isEmpty) throw AiError('No steps came back. Try again.');
  return out;
}

/// Asks the chosen AI for steps for [t].
Future<List<AiStep>> breakDown(AppData data, Task t, {required String claudeKey, http.Client? client, DateTime? now}) async {
  final c = client ?? http.Client();
  try {
    return data.aiProvider == 'ollama'
        ? await _ollama(c, data, t, now ?? DateTime.now())
        : await _claude(c, data, t, claudeKey, now ?? DateTime.now());
  } on TimeoutException {
    throw AiError('No answer in time. Try again.');
  } on http.ClientException catch (e) {
    throw AiError(data.aiProvider == 'ollama'
        ? 'Couldn\'t reach Ollama at ${data.ollamaUrl}. Is it running, set to listen on the network, and are you on the same Wi-Fi? ($e)'
        : 'Couldn\'t reach Claude. Check the internet connection. ($e)');
  } finally {
    if (client == null) c.close();
  }
}

Future<List<AiStep>> _claude(http.Client c, AppData data, Task t, String key, DateTime now) async {
  if (key.trim().isEmpty) throw AiError('Add your Claude API key in Settings, Smart helpers.');
  final res = await c
      .post(
        Uri.https('api.anthropic.com', '/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': key.trim(),
          'anthropic-version': '2026-10-21',
          // If a safety check declines, the API answers with another model instead of stopping.
          'anthropic-beta': 'server-side-fallback-2026-07-01',
        },
        body: jsonEncode({
          'model': claudeModel,
          'max_tokens': 16000,
          'fallbacks': 'default',
          'system': _system(data),
          'output_config': {
            'effort': 'low',
            'format': {'type': 'json_schema', 'schema': _schema},
          },
          'messages': [
            {'role': 'user', 'content': _prompt(data, t, now)},
          ],
        }),
      )
      .timeout(const Duration(seconds: 120));
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {
    throw AiError('Claude sent an answer the app couldn\'t read (${res.statusCode}).');
  }
  if (res.statusCode != 200) {
    final msg = (j['error'] as Map?)?['message'] as String? ?? 'error ${res.statusCode}';
    throw AiError(switch (res.statusCode) {
      401 => 'Claude didn\'t accept the API key. Check it in Settings, Smart helpers.',
      403 => 'This API key isn\'t allowed to do that: $msg',
      429 => 'Claude is busy or the key is out of credit. Try again in a minute. ($msg)',
      >= 500 => 'Claude is having trouble right now. Try again in a minute.',
      _ => 'Claude said: $msg',
    });
  }
  if (j['stop_reason'] == 'refusal') throw AiError('Claude declined to break this one down.');
  final text = [
    for (final b in j['content'] as List? ?? const [])
      if (b is Map && b['type'] == 'text') b['text'] as String? ?? '',
  ].join();
  return _parse(text);
}

Future<List<AiStep>> _ollama(http.Client c, AppData data, Task t, DateTime now) async {
  var base = data.ollamaUrl;
  if (base.isEmpty) throw AiError('Add your Ollama address in Settings, Smart helpers.');
  if (!base.startsWith('http')) base = 'http://$base';
  final uri = Uri.tryParse(base.endsWith('/') ? '${base}api/chat' : '$base/api/chat');
  if (uri == null) throw AiError('The Ollama address doesn\'t look right: ${data.ollamaUrl}');
  final res = await c
      .post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'model': data.ollamaModel,
          'stream': false,
          'format': _schema,
          'messages': [
            {'role': 'system', 'content': _system(data)},
            {'role': 'user', 'content': _prompt(data, t, now)},
          ],
        }),
      )
      .timeout(const Duration(seconds: 180));
  if (res.statusCode != 200) {
    var msg = 'error ${res.statusCode}';
    try {
      msg = (jsonDecode(res.body) as Map)['error'] as String? ?? msg;
    } catch (_) {}
    throw AiError(res.statusCode == 404 ? 'Ollama doesn\'t have the model "${data.ollamaModel}" ($msg).' : 'Ollama said: $msg');
  }
  final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  return _parse((j['message'] as Map?)?['content'] as String? ?? '');
}

/// The steps to add for [picked] suggestions: their lengths (in hours, or the working days they
/// fill) and links among the ones picked.
List<TaskStep> stepsFrom(List<AiStep> all, Set<int> picked, AppData data) {
  final out = <int, TaskStep>{};
  for (var i = 0; i < all.length; i++) {
    if (!picked.contains(i)) continue;
    final a = all[i];
    out[i] = TaskStep.create(a.title)
      ..takesMinutes = a.minutes
      ..takesDays = daysForMinutes(a.minutes, data);
  }
  out.forEach((i, s) {
    for (final j in all[i].after) {
      final p = out[j];
      if (p != null) s.afterIds.add(p.id);
    }
  });
  return [for (var i = 0; i < all.length; i++) ?out[i]];
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_blocks/ai_breakdown.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/ai_sheet.dart';

/// Item 114 G: AI step breakdown with Claude or Ollama.
void main() {
  const answer = {
    'steps': [
      {'title': 'Pull last year of sales', 'minutes': 60, 'after': []},
      {'title': 'Clean outliers', 'minutes': 120, 'after': [0]},
      {'title': 'Fit the forecast', 'minutes': 900, 'after': [1, 5, -1]},
    ],
  };

  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  AppStore store() {
    final s = AppStore();
    s.setHelper(Helper.aiBreakdown, true);
    return s;
  }

  test('off until turned on', () {
    expect(AppStore().data.helperOn(Helper.aiBreakdown), isFalse);
  });

  test('Claude: sends only the task, asks for the schema, reads the steps', () async {
    final s = store();
    s.data.aiAbout = 'Data analyst in supply chain';
    final t = s.addTask('Demand forecast')..notes = 'Weekly, by SKU';
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final c = MockClient((r) async {
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      headers = r.headers;
      sent = jsonDecode(r.body) as Map<String, dynamic>;
      return json({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(answer)},
        ],
      });
    });
    final steps = await breakDown(s.data, t, claudeKey: ' sk-ant-x ', client: c);
    expect(headers['x-api-key'], 'sk-ant-x');
    expect(sent['model'], claudeModel);
    expect((sent['output_config'] as Map)['format']['type'], 'json_schema');
    expect(sent['system'], contains('Data analyst in supply chain'));
    expect((sent['messages'] as List).single['content'], allOf(contains('Demand forecast'), contains('Weekly, by SKU')));
    expect(steps.map((x) => x.title), ['Pull last year of sales', 'Clean outliers', 'Fit the forecast']);
    expect(steps[2].after, [1], reason: 'only earlier places are kept');
  });

  test('Claude: no key, bad key, refusal', () async {
    final s = store();
    final t = s.addTask('X');
    final never = MockClient((_) async => fail('should not call'));
    await expectLater(breakDown(s.data, t, claudeKey: '', client: never),
        throwsA(isA<AiError>().having((e) => e.message, 'message', contains('Add your Claude API key'))));
    final bad = MockClient((_) async => json({
          'type': 'error',
          'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'},
        }, 401));
    await expectLater(breakDown(s.data, t, claudeKey: 'k', client: bad),
        throwsA(isA<AiError>().having((e) => e.message, 'message', contains('didn\'t accept'))));
    final refused = MockClient((_) async => json({'stop_reason': 'refusal', 'content': []}));
    await expectLater(breakDown(s.data, t, claudeKey: 'k', client: refused),
        throwsA(isA<AiError>().having((e) => e.message, 'message', contains('declined'))));
    final junk = MockClient((_) async => json({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'not json'},
          ],
        }));
    await expectLater(breakDown(s.data, t, claudeKey: 'k', client: junk), throwsA(isA<AiError>()));
  });

  test('Ollama: posts to /api/chat on the home network', () async {
    final s = store();
    s.data
      ..aiProvider = 'ollama'
      ..ollamaUrl = '192.168.1.20:11434/'
      ..ollamaModel = 'qwen3';
    final t = s.addTask('Safety stock');
    final c = MockClient((r) async {
      expect(r.url.toString(), 'http://192.168.1.20:11434/api/chat');
      final b = jsonDecode(r.body) as Map;
      expect(b['model'], 'qwen3');
      expect(b['stream'], false);
      expect(b['format'], isA<Map>());
      return json({
        'message': {'role': 'assistant', 'content': jsonEncode(answer)},
      });
    });
    final steps = await breakDown(s.data, t, claudeKey: '', client: c);
    expect(steps, hasLength(3));

    final missing = MockClient((_) async => json({'error': 'model "qwen3" not found'}, 404));
    await expectLater(breakDown(s.data, t, claudeKey: '', client: missing),
        throwsA(isA<AiError>().having((e) => e.message, 'message', contains('doesn\'t have the model'))));
    final down = MockClient((_) async => throw http.ClientException('Connection refused'));
    await expectLater(breakDown(s.data, t, claudeKey: '', client: down),
        throwsA(isA<AiError>().having((e) => e.message, 'message', contains('same Wi-Fi'))));
    s.data.ollamaUrl = '';
    await expectLater(breakDown(s.data, t, claudeKey: '', client: c), throwsA(isA<AiError>()));
  });

  test('picked steps keep their lengths and the links among them', () {
    final s = store();
    final t = s.addTask('Forecast');
    final all = [AiStep('A', 60, []), AiStep('B', 120, [0]), AiStep('C', 900, [0, 1])];
    final out = stepsFrom(all, {0, 2}, s.data);
    expect(out.map((x) => x.title), ['A', 'C']);
    expect(out[0].takesMinutes, 60);
    expect(out[1].takesDays, greaterThanOrEqualTo(2));
    expect(out[1].afterIds, [out[0].id], reason: 'B was not picked, so only the link to A stays');
    expect(s.addAiSteps(t, out), 2);
    expect(t.steps.map((x) => x.title), ['A', 'C']);
  });

  test('the Claude key stays out of the backup', () {
    final s = store()..claudeKey = 'sk-ant-secret';
    expect(jsonEncode(s.deviceSettingsBackup()), isNot(contains('sk-ant-secret')));
    expect(jsonEncode(s.data.toJson()), isNot(contains('sk-ant-secret')));
  });

  testWidgets('the sheet shows the steps and adds the ticked ones', (tester) async {
    final s = store();
    final t = s.addTask('Demand forecast');
    s.claudeKey = 'k';
    final c = MockClient((_) async => json({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': jsonEncode(answer)},
          ],
        }));
    var added = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => added = await showAiBreakdown(context, s, t, client: c),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Clean outliers'), findsOneWidget);
    expect(find.text('Add 3 steps'), findsOneWidget);
    await tester.tap(find.text('Clean outliers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 2 steps'));
    await tester.pumpAndSettle();
    expect(added, 2);
    expect(t.steps.map((x) => x.title), ['Pull last year of sales', 'Fit the forecast']);
  });
}

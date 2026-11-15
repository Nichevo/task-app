import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 1.12.5: finds addresses for a task's location with OpenStreetMap's free search (Nominatim).
/// Only what is typed is sent, and only when Search is pressed.
Future<List<TaskWhere>> searchAddress(String query, {http.Client? client}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': q, 'format': 'jsonv2', 'limit': '6'});
  final c = client ?? http.Client();
  try {
    final r = await c.get(uri, headers: {'User-Agent': 'TaskBlocks/1.12 (task app)', 'Accept-Language': 'en'});
    if (r.statusCode != 200) throw Exception('search failed (${r.statusCode})');
    return parseAddresses(jsonDecode(r.body));
  } finally {
    if (client == null) c.close();
  }
}

/// The results of a Nominatim search as locations.
List<TaskWhere> parseAddresses(Object? json) => [
      if (json is List)
        for (final j in json)
          if (j is Map && double.tryParse('${j['lat']}') != null && double.tryParse('${j['lon']}') != null)
            TaskWhere(shortAddress('${j['display_name'] ?? ''}'),
                lat: double.parse('${j['lat']}'), lng: double.parse('${j['lon']}')),
    ];

/// "12 Queen Street, Auckland Central, Auckland, 1010, New Zealand" is long for a task: keeps
/// the first three parts.
String shortAddress(String full) {
  final parts = full.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  return parts.take(3).join(', ');
}

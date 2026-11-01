import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../changelog.dart';

const projectUrl = 'https://github.com/Nichevo/task-app';

/// The installed version and build, e.g. "1.4.0 (build 57)"; null if it can't be read.
Future<String?> appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty || info.buildNumber == info.version
        ? info.version
        : '${info.version} (build ${info.buildNumber})';
  } catch (_) {
    return null;
  }
}

/// Settings, About: version, changelog and a link to the project.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hint = TextStyle(color: Theme.of(context).hintColor);
    return Scaffold(
      appBar: AppBar(title: const Text('About Task Blocks')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<String?>(
          future: appVersion(),
          builder: (context, snap) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(snap.data ?? releases.first.version),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code),
          title: const Text('Project on GitHub'),
          subtitle: const Text(projectUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(projectUrl), mode: LaunchMode.externalApplication),
        ),
        const Divider(height: 32),
        Text('What\'s new', style: Theme.of(context).textTheme.titleMedium),
        for (final r in releases) ...[
          const SizedBox(height: 12),
          Text('${r.version}  ·  ${r.date}', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final c in r.changes)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: hint),
                Expanded(child: Text(c)),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// The "What's new" pop-up for [release].
Future<void> showWhatsNew(BuildContext context, Release release) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('What\'s new in ${release.version}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final ch in release.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  '),
                  Expanded(child: Text(ch)),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
            },
            child: const Text('Earlier versions'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );

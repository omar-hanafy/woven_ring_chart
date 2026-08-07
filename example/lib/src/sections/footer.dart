import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../package_info.dart';
import '../showcase_theme.dart';

/// Where to go next.
class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1, color: ShowcaseColors.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ShowcaseLayout.maxContentWidth,
              ),
              child: Padding(
                padding: ShowcaseLayout.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'This page is the package example.',
                      style: ShowcaseText.cardTitle,
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: const Text(
                        'Every chart above is the real widget, running. The '
                        'source is example/lib in the repository, and it '
                        'redeploys itself on every push to main that touches '
                        'the package or the example.',
                        style: ShowcaseText.body,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const <Widget>[
                        _FooterLink(label: 'pub.dev', url: kPubDevUrl),
                        _FooterLink(label: 'GitHub', url: kRepoUrl),
                        _FooterLink(label: 'API docs', url: kApiDocsUrl),
                        _FooterLink(
                          label: 'MIT licence',
                          url: '$kRepoUrl/blob/main/LICENSE',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: ValueKey<String>('footer-link-$label'),
      onPressed: () => launchUrl(Uri.parse(url)),
      style: OutlinedButton.styleFrom(
        foregroundColor: ShowcaseColors.ink,
        side: const BorderSide(color: ShowcaseColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

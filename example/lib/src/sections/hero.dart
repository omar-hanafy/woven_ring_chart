import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../package_info.dart';
import '../showcase_theme.dart';

/// The top of the page: what this is, what it looks like, how to get it.
///
/// The ring here is the real widget playing its real entrance animation. A
/// visitor sees the chart draw itself before reading a single word about it.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ShowcaseLayout.maxContentWidth,
        ),
        child: Padding(
          padding: ShowcaseLayout.pagePadding.add(
            const EdgeInsets.symmetric(vertical: 64),
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool wide =
                  constraints.maxWidth >= ShowcaseLayout.sideBySideBreakpoint;
              const Widget ring = _HeroRing();
              final Widget words = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('woven_ring_chart', style: ShowcaseText.wordmark),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: const Text(
                      'A doughnut chart for Flutter whose segments lap over one '
                      'another like shingles. There is no straight radial line '
                      'anywhere: every boundary between two colours is a true '
                      'semicircle, including the seam.',
                      style: ShowcaseText.lede,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _InstallChip(),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      _LinkButton(
                        label: 'pub.dev',
                        icon: Icons.inventory_2_outlined,
                        url: kPubDevUrl,
                      ),
                      const SizedBox(width: 8),
                      _LinkButton(
                        label: 'GitHub',
                        icon: Icons.code_rounded,
                        url: kRepoUrl,
                      ),
                      const SizedBox(width: 8),
                      _LinkButton(
                        label: 'API docs',
                        icon: Icons.menu_book_outlined,
                        url: kApiDocsUrl,
                      ),
                    ],
                  ),
                ],
              );

              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    words,
                    const SizedBox(height: 40),
                    const Center(child: ring),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: words),
                  const SizedBox(width: 48),
                  ring,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroRing extends StatelessWidget {
  const _HeroRing();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 280,
      child: WovenRingChart(
        key: ValueKey<String>('hero-ring'),
        segments: <WovenSegment>[
          WovenSegment(value: 37, fill: WovenFill.solid(WovenPalette.purple)),
          WovenSegment(value: 19, fill: WovenFill.solid(WovenPalette.green)),
          WovenSegment(value: 29, fill: WovenFill.solid(WovenPalette.amber)),
          WovenSegment(value: 15, fill: WovenFill.solid(WovenPalette.rose)),
        ],
        style: WovenRingStyle(surfaceColor: ShowcaseColors.page),
        semanticLabel: 'A four segment woven ring',
      ),
    );
  }
}

/// The dependency line, with a button that puts it on the clipboard.
class _InstallChip extends StatefulWidget {
  const _InstallChip();

  @override
  State<_InstallChip> createState() => _InstallChipState();
}

class _InstallChipState extends State<_InstallChip> {
  Timer? _revert;
  bool _justCopied = false;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ShowcaseColors.surface,
          border: Border.all(color: ShowcaseColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  kInstallLine,
                  key: const ValueKey<String>('install-line'),
                  overflow: TextOverflow.ellipsis,
                  style: ShowcaseText.code.copyWith(
                    color: ShowcaseColors.ink,
                    fontSize: 14.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const ValueKey<String>('copy-install-button'),
                onPressed: _copy,
                style: TextButton.styleFrom(
                  foregroundColor: _justCopied
                      ? WovenPalette.green
                      : ShowcaseColors.muted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _justCopied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                ),
                label: Text(
                  _justCopied ? 'Copied' : 'Copy',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: kInstallLine));
    if (!mounted) return;
    setState(() => _justCopied = true);
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }
}

/// A quiet outward link.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final IconData icon;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: ValueKey<String>('link-$label'),
      onPressed: () => launchUrl(Uri.parse(url)),
      style: TextButton.styleFrom(
        foregroundColor: ShowcaseColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

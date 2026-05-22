import 'package:flutter/material.dart';

/// Renders a unified-diff string (typically the output of
/// `GitRepo.diffTreeToTree` / `GitRepo.diffWorkdir`) with line-level
/// coloring: additions green, removals red, hunk headers blue. Monospace,
/// selectable so the user can copy a hunk.
class TextDiffView extends StatelessWidget {
  const TextDiffView({required this.diffText, super.key});

  final String diffText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      height: 1.4,
    );

    final scheme = theme.colorScheme;
    final addColor = Colors.green.withValues(alpha: 0.25);
    final removeColor = Colors.red.withValues(alpha: 0.25);
    final hunkColor = scheme.primaryContainer.withValues(alpha: 0.45);

    final spans = <TextSpan>[];
    for (final line in diffText.split('\n')) {
      Color? background;
      if (line.startsWith('+++') || line.startsWith('---')) {
        // File headers — neutral.
      } else if (line.startsWith('@@')) {
        background = hunkColor;
      } else if (line.startsWith('+')) {
        background = addColor;
      } else if (line.startsWith('-')) {
        background = removeColor;
      }
      spans.add(
        TextSpan(
          text: '$line\n',
          style: background == null
              ? base
              : base.copyWith(backgroundColor: background),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectableText.rich(TextSpan(children: spans)),
    );
  }
}

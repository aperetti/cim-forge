import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';
import 'package:flutter/material.dart';

/// Renders the raw XML source as monospace text, optionally highlighting one
/// [SourceSpan] (e.g. a selected element's full extent). FR-4.5.
class RawXmlView extends StatelessWidget {
  const RawXmlView({required this.source, this.highlight, super.key});

  final String source;
  final SourceSpan? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      height: 1.4,
    );
    final hl = highlight;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText.rich(
        TextSpan(
          children: hl == null
              ? [TextSpan(text: source, style: mono)]
              : [
                  TextSpan(text: source.substring(0, hl.start), style: mono),
                  TextSpan(
                    text: source.substring(hl.start, hl.stop),
                    style: mono.copyWith(
                      backgroundColor:
                          theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: source.substring(hl.stop), style: mono),
                ],
        ),
      ),
    );
  }
}

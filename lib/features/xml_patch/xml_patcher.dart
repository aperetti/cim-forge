import 'package:meta/meta.dart';

/// A single text-range replacement. `[start, stop)` characters of the source
/// are replaced by [replacement]. Half-open, like `SourceSpan`.
@immutable
class TextEdit {
  const TextEdit({
    required this.start,
    required this.stop,
    required this.replacement,
  });

  final int start;
  final int stop;
  final String replacement;

  int get length => stop - start;

  @override
  bool operator ==(Object other) =>
      other is TextEdit &&
      other.start == start &&
      other.stop == stop &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(start, stop, replacement);

  @override
  String toString() => 'TextEdit($start..$stop -> "$replacement")';
}

class OverlappingEditException implements Exception {
  OverlappingEditException(this.first, this.second);
  final TextEdit first;
  final TextEdit second;
  @override
  String toString() =>
      'OverlappingEditException: $first overlaps $second';
}

/// Applies non-overlapping text edits to [source] and returns the patched
/// string. Edits are sorted by start ascending; overlap is rejected with
/// [OverlappingEditException]. Negative or out-of-range edits throw
/// [RangeError].
///
/// Implementation walks left-to-right with a cursor — equivalent to applying
/// right-to-left but avoids the O(N²) cost of repeated `replaceRange`.
String applyTextEdits(String source, List<TextEdit> edits) {
  if (edits.isEmpty) return source;
  final sorted = [...edits]..sort((a, b) => a.start.compareTo(b.start));

  for (final edit in sorted) {
    if (edit.start < 0 || edit.stop > source.length || edit.start > edit.stop) {
      throw RangeError(
        'invalid edit $edit against source of length ${source.length}',
      );
    }
  }

  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].start < sorted[i - 1].stop) {
      throw OverlappingEditException(sorted[i - 1], sorted[i]);
    }
  }

  final buf = StringBuffer();
  var cursor = 0;
  for (final edit in sorted) {
    buf
      ..write(source.substring(cursor, edit.start))
      ..write(edit.replacement);
    cursor = edit.stop;
  }
  buf.write(source.substring(cursor));
  return buf.toString();
}

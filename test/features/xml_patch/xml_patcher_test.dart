import 'package:cim_forge/features/xml_patch/xml_patcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyTextEdits', () {
    test('returns input unchanged when no edits supplied', () {
      expect(applyTextEdits('abc', const []), 'abc');
    });

    test('applies a single replacement', () {
      const source = 'hello world';
      final result = applyTextEdits(
        source,
        const [TextEdit(start: 6, stop: 11, replacement: 'flutter')],
      );
      expect(result, 'hello flutter');
    });

    test('applies multiple non-overlapping replacements left-to-right', () {
      const source = 'aaa BBB ccc';
      final result = applyTextEdits(
        source,
        const [
          TextEdit(start: 0, stop: 3, replacement: 'AAA'),
          TextEdit(start: 8, stop: 11, replacement: 'CCC'),
        ],
      );
      expect(result, 'AAA BBB CCC');
    });

    test('sorts input edits by start before applying', () {
      const source = 'aaa BBB ccc';
      final result = applyTextEdits(
        source,
        const [
          TextEdit(start: 8, stop: 11, replacement: 'CCC'),
          TextEdit(start: 0, stop: 3, replacement: 'AAA'),
        ],
      );
      expect(result, 'AAA BBB CCC');
    });

    test('insertion at a zero-length span widens the source', () {
      const source = '<a/>';
      final result = applyTextEdits(
        source,
        const [TextEdit(start: 4, stop: 4, replacement: '<b/>')],
      );
      expect(result, '<a/><b/>');
    });

    test('rejects overlapping edits', () {
      expect(
        () => applyTextEdits(
          'abcdef',
          const [
            TextEdit(start: 0, stop: 3, replacement: 'XXX'),
            TextEdit(start: 2, stop: 5, replacement: 'YYY'),
          ],
        ),
        throwsA(isA<OverlappingEditException>()),
      );
    });

    test('rejects out-of-range edits', () {
      expect(
        () => applyTextEdits(
          'abc',
          const [TextEdit(start: 0, stop: 100, replacement: 'X')],
        ),
        throwsRangeError,
      );
    });
  });
}

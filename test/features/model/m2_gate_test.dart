import 'dart:io';

import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M2 gate — hand-authored fixtures', () {
    test('every parsed Element has non-null source spans', () {
      final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
      final g = ObjectGraph.parse(src);
      for (final el in g.elements) {
        expect(el.id, isNotEmpty);
        expect(el.headerSpan.length, greaterThan(0));
        expect(el.idAttributeSpan.length, greaterThan(0));
        expect(el.closingSpan, isNotNull);
        for (final a in el.attributes) {
          expect(a.elementSpan.length, greaterThan(0));
          expect(a.textSpan.length, greaterThanOrEqualTo(0));
        }
        for (final a in el.associations) {
          expect(a.elementSpan.length, greaterThan(0));
          expect(a.targetSpan.length, greaterThan(0));
        }
      }
    });

    test('every parsed element references a class known to the metamodel '
        'and every attribute resolves through inheritance', () {
      final modelSrc = File('test/fixtures/cim/sample.xml').readAsStringSync();
      final schemaSrc =
          File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync();
      final g = ObjectGraph.parse(modelSrc);
      final m = SchemaLoader.load(schemaSrc);

      for (final el in g.elements) {
        final cls = m.classByName(el.className);
        expect(cls, isNotNull, reason: 'unknown class ${el.className}');

        final legalAttrs = m
            .attributesOf(el.className)
            .map((a) => a.name)
            .toSet();
        final legalAssocs = m
            .associationsOf(el.className)
            .map((a) => a.name)
            .toSet();

        for (final a in el.attributes) {
          expect(
            legalAttrs.contains(a.shortName),
            isTrue,
            reason:
                '${el.className}.${a.shortName} not declared in metamodel',
          );
        }
        for (final a in el.associations) {
          expect(
            legalAssocs.contains(a.shortName),
            isTrue,
            reason: '${el.className}.${a.shortName} association '
                'not declared in metamodel',
          );
        }
      }
    });

    test('no-op round-trip preserves the source byte-for-byte', () {
      // The "easy half" of TR-11.3: parse without mutating → the surface that
      // surgical patches operate on must reproduce the original bytes when
      // no edits are applied. Since ObjectGraph holds [source] as-is and the
      // M4 patcher will apply edits against this exact buffer, this is the
      // anchor that keeps surgical patches honest.
      final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
      final g = ObjectGraph.parse(src);
      expect(g.source, src);
    });
  });

  group('M2 gate — real-world fixture', () {
    test('ACEP_PSIL position invariants hold over the whole file', () {
      const path = 'test/fixtures/cim/ACEP_PSIL.xml';
      if (!File(path).existsSync()) {
        markTestSkipped('fixture not present: $path');
        return;
      }
      final src = File(path).readAsStringSync();
      final g = ObjectGraph.parse(src);
      expect(g.elementCount, greaterThan(50));
      for (final el in g.elements) {
        expect(el.headerSpan.start, lessThan(el.headerSpan.stop));
        for (final a in el.attributes) {
          expect(a.elementSpan.start, lessThan(a.elementSpan.stop));
          // textSpan may have zero length for empty scalars but must be inside
          // the element span.
          expect(
            a.textSpan.start,
            greaterThanOrEqualTo(a.elementSpan.start),
          );
          expect(a.textSpan.stop, lessThanOrEqualTo(a.elementSpan.stop));
        }
        for (final a in el.associations) {
          expect(
            a.targetSpan.start,
            greaterThanOrEqualTo(a.elementSpan.start),
          );
          expect(a.targetSpan.stop, lessThanOrEqualTo(a.elementSpan.stop));
        }
      }
    });

    test('ACEP_PSIL no-op round-trip is byte-equal', () {
      const path = 'test/fixtures/cim/ACEP_PSIL.xml';
      if (!File(path).existsSync()) {
        markTestSkipped('fixture not present: $path');
        return;
      }
      final src = File(path).readAsStringSync();
      final g = ObjectGraph.parse(src);
      expect(g.source, src);
    });
  });
}

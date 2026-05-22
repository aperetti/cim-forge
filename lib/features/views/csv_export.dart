import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';

/// Exports the rendered rows of [view] from [database] as RFC 4180 CSV.
/// FR-7.3. Composite-view slot columns are flattened into the header row
/// the same way the grid renders them.
String exportViewAsCsv(
  AppDatabase database,
  QueryEngine engine,
  ViewDefinition view, {
  int chunkSize = 1000,
}) {
  final headers = <String>[
    for (final c in view.columns) c.displayName(),
    for (final inclusion in view.inclusions)
      for (var slot = 0; slot < inclusion.maxCount; slot++)
        for (final attr in inclusion.attributes)
          '${inclusion.displayLabel()} #${slot + 1} $attr',
  ];

  final buf = StringBuffer()..writeln(headers.map(_csvField).join(','));

  final total = engine.countMatching(database, view);
  for (var offset = 0; offset < total; offset += chunkSize) {
    final rows = engine.execute(
      database,
      view,
      limit: chunkSize,
      offset: offset,
    );
    for (final row in rows) {
      final cells = <String>[...row.values.map((v) => v ?? '')];
      for (var i = 0; i < row.slots.length; i++) {
        final inclusionSlots = row.slots[i];
        final perSlot = _attributesPerSlot(view, i);
        for (var slot = 0; slot < inclusionSlots.slots.length; slot++) {
          final child = inclusionSlots.slots[slot];
          if (child == null) {
            cells.addAll(List<String>.filled(perSlot, ''));
          } else {
            cells.addAll(child.values.map((v) => v ?? ''));
          }
        }
      }
      buf.writeln(cells.map(_csvField).join(','));
    }
  }

  return buf.toString();
}

int _attributesPerSlot(ViewDefinition view, int inclusionIndex) =>
    view.inclusions[inclusionIndex].attributes.length;

String _csvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

import 'package:cim_forge/features/diff/semantic_diff.dart';
import 'package:cim_forge/features/model/element.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:meta/meta.dart';

@immutable
class CellChange {
  const CellChange({required this.oldValue, required this.newValue});
  final String? oldValue;
  final String? newValue;
}

@immutable
class ViewRowDiff {
  const ViewRowDiff({required this.elementId, required this.cellChanges});

  /// Id of the base element backing this row.
  final String elementId;

  /// Column index → change. Only columns affected by the row's change appear.
  final Map<int, CellChange> cellChanges;
}

@immutable
class ViewDiff {
  const ViewDiff({
    required this.rowsAdded,
    required this.rowsRemoved,
    required this.rowsModified,
  });

  /// Projects a [SemanticDiff] through [view]'s column list. For M7 only
  /// direct-attribute columns (path length 1) and direct association
  /// columns are surfaced; joined-path columns are left for the M9 polish
  /// pass where projecting them needs both graphs in hand to walk joins.
  factory ViewDiff.project(SemanticDiff diff, ViewDefinition view) {
    final added = diff.added
        .where((el) => el.className == view.baseClass)
        .toList(growable: false);
    final removed = diff.removed
        .where((el) => el.className == view.baseClass)
        .toList(growable: false);

    final modified = <ViewRowDiff>[];
    for (final elDiff in diff.modified) {
      if (elDiff.className != view.baseClass) continue;
      final cellChanges = <int, CellChange>{};
      for (var i = 0; i < view.columns.length; i++) {
        final column = view.columns[i];
        if (column.path.length != 1) continue; // joined: skip for M7
        final name = column.path.single;
        final attrChange = elDiff.attributeChanges[name];
        if (attrChange != null) {
          cellChanges[i] = CellChange(
            oldValue: attrChange.oldValue,
            newValue: attrChange.newValue,
          );
          continue;
        }
        final assocChange = elDiff.associationChanges[name];
        if (assocChange != null) {
          cellChanges[i] = CellChange(
            oldValue: assocChange.oldTargetId,
            newValue: assocChange.newTargetId,
          );
        }
      }
      if (cellChanges.isNotEmpty) {
        modified.add(
          ViewRowDiff(
            elementId: elDiff.id,
            cellChanges: Map.unmodifiable(cellChanges),
          ),
        );
      }
    }

    return ViewDiff(
      rowsAdded: added,
      rowsRemoved: removed,
      rowsModified: List.unmodifiable(modified),
    );
  }

  /// Elements newly visible through this view (added base-class elements).
  final List<CimElement> rowsAdded;

  /// Elements that disappeared from this view's projection.
  final List<CimElement> rowsRemoved;

  /// Existing rows whose cells changed.
  final List<ViewRowDiff> rowsModified;

  bool get isEmpty =>
      rowsAdded.isEmpty && rowsRemoved.isEmpty && rowsModified.isEmpty;
}

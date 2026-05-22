import 'package:cim_forge/features/editing/edit_journal.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:flutter_test/flutter_test.dart';

SetAttributeValueOp _op(String id, String value) => SetAttributeValueOp(
  elementId: id,
  attributeName: 'name',
  newValue: value,
  oldValue: 'prev-$value',
);

void main() {
  group('EditJournal basic push/undo/redo', () {
    test('push records ops and exposes them on the undo stack', () {
      final j = EditJournal()
        ..push(_op('e1', 'A'))
        ..push(_op('e2', 'B'));
      expect(j.canUndo, isTrue);
      expect(j.canRedo, isFalse);
      expect(j.undoStack.length, 2);
    });

    test('undo returns the inverted op and shifts the cursor', () {
      final j = EditJournal()..push(_op('e1', 'A'));
      final inverted = j.undo();
      expect(inverted, isA<SetAttributeValueOp>());
      expect(j.canUndo, isFalse);
      expect(j.canRedo, isTrue);
    });

    test('redo returns the original op', () {
      final j = EditJournal()..push(_op('e1', 'A'))..undo();
      final restored = j.redo() as SetAttributeValueOp;
      expect(restored.elementId, 'e1');
      expect(restored.newValue, 'A');
    });

    test('a fresh push after undo truncates the redo tail', () {
      final j = EditJournal()
        ..push(_op('e1', 'A'))
        ..push(_op('e2', 'B'))
        ..undo() // e2 is now on redo stack
        ..push(_op('e3', 'C'));
      expect(j.redoStack, isEmpty);
      expect(j.undoStack.length, 2);
    });

    test('undo and redo throw on empty stacks', () {
      final j = EditJournal();
      expect(j.undo, throwsStateError);
      expect(j.redo, throwsStateError);
    });
  });

  group('EditJournal grouping', () {
    test('beginGroup/endGroup commits as one composite when > 1 op', () {
      final j = EditJournal()
        ..beginGroup('rename batch')
        ..push(_op('e1', 'A'))
        ..push(_op('e2', 'B'))
        ..endGroup();
      expect(j.undoStack.length, 1);
      final entry = j.undoStack.single as CompositeOp;
      expect(entry.label, 'rename batch');
      expect(entry.children.length, 2);
    });

    test('a single op inside a group commits as itself, not a composite', () {
      final j = EditJournal()
        ..beginGroup('one')
        ..push(_op('e1', 'A'))
        ..endGroup();
      expect(j.undoStack.single, isA<SetAttributeValueOp>());
    });

    test('an empty group commits nothing', () {
      final j = EditJournal()
        ..beginGroup('empty')
        ..endGroup();
      expect(j.undoStack, isEmpty);
    });

    test('canUndo/canRedo are false while a group is open', () {
      final j = EditJournal()
        ..push(_op('e1', 'A'))
        ..beginGroup('open');
      expect(j.canUndo, isFalse);
      j
        ..endGroup()
        ..beginGroup('again');
      expect(j.canUndo, isFalse);
    });

    test('nested groups commit on the outermost endGroup', () {
      final j = EditJournal()
        ..beginGroup('outer')
        ..push(_op('e1', 'A'))
        ..beginGroup('inner')
        ..push(_op('e2', 'B'))
        ..endGroup();
      // Inner closed but outer still open.
      expect(j.undoStack, isEmpty);
      j.endGroup();
      expect(j.undoStack.length, 1);
    });

    test('endGroup without matching begin throws', () {
      final j = EditJournal();
      expect(j.endGroup, throwsStateError);
    });
  });

  group('CompositeOp inversion', () {
    test('reverses child order and inverts each child', () {
      const composite = CompositeOp(
        label: 'b',
        children: [
          SetAttributeValueOp(
            elementId: 'e1',
            attributeName: 'name',
            newValue: 'A',
            oldValue: 'a',
          ),
          SetAttributeValueOp(
            elementId: 'e2',
            attributeName: 'name',
            newValue: 'B',
            oldValue: 'b',
          ),
        ],
      );
      final inv = composite.invert();
      expect(inv.children.first, isA<SetAttributeValueOp>());
      expect((inv.children.first as SetAttributeValueOp).elementId, 'e2');
      expect((inv.children.first as SetAttributeValueOp).newValue, 'b');
    });
  });
}

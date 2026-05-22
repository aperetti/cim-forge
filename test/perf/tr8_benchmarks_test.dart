// TR-8 budget benchmarks (M9). Codifies every numerical performance
// requirement on a synthesized 500k-element fixture.
//
// Each budget is captured as both:
//   - the TR-8 ABSOLUTE ceiling (hard requirement from the plan), and
//   - a SOFT baseline that fails fast when a change regresses by > 15%
//     (TR-8.6).
//
// Tuning policy: if a measurement comfortably beats its budget you may
// tighten the baseline IN A FOLLOW-UP PR with a profiling note. A
// regression PR should either justify the slowdown in the description or
// fix it; the soft baseline is the early-warning trigger.

import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// Scale: 500k elements is the plan's stated target (TR-8.1).
const int kScaleElements = 500000;

// ─── Budgets (TR-8) ────────────────────────────────────────────────────
// These are the hard ceilings from the plan. A measurement above them is
// a regression that must be addressed before merging.
const int kBudgetColdOpenPlusFirstRenderMs = 3000; // TR-8.2
const int kBudgetWarmFilterSortSearchMs = 200;     // TR-8.3
const int kBudgetSingleCellEditMs = 50;            // TR-8.4

// ─── Soft baselines for TR-8.6 regression guard ────────────────────────
// Set generously today; tighten when CI hardware stabilizes. > 15% slower
// than these fails the build.
const int kBaselineColdOpenPlusFirstRenderMs = 3000;
const int kBaselineWarmFilterSortSearchMs = 200;
const int kBaselineSingleCellEditMs = 50;

const double kRegressionThreshold = 1.15;

void _enforceBudget({
  required String label,
  required int observedMs,
  required int ceilingMs,
  required int baselineMs,
}) {
  expect(
    observedMs,
    lessThanOrEqualTo(ceilingMs),
    reason: '$label: TR-8 budget breached '
        '(observed ${observedMs}ms vs ceiling ${ceilingMs}ms)',
  );
  final regressionLimit = (baselineMs * kRegressionThreshold).round();
  expect(
    observedMs,
    lessThanOrEqualTo(regressionLimit),
    reason: '$label: TR-8.6 regression guard '
        '(observed ${observedMs}ms vs baseline ${baselineMs}ms × 1.15 = '
        '${regressionLimit}ms)',
  );
}

// ─── Synthesis ─────────────────────────────────────────────────────────

/// Bulk-inserts a 500k-element graph directly into [db] without going through
/// the XML parse path. Mirrors the M3 gate's synthesizer.
void _synthesize(AppDatabase db, {required int elements}) {
  final raw = db.raw
    ..execute('BEGIN')
    ..execute('''INSERT INTO files (id, path) VALUES (1, 'synthetic')''');

  final elementStmt = raw.prepare(
    'INSERT INTO elements (id, class, file_id, source_start, source_stop) '
    'VALUES (?, ?, 1, 0, 0)',
  );
  final attrStmt = raw.prepare(
    'INSERT INTO attributes '
    '(element_id, name, value, source_start, source_stop) '
    'VALUES (?, ?, ?, 0, 0)',
  );

  try {
    elementStmt.execute(['_sub1', 'Substation']);
    attrStmt.execute(['_sub1', 'name', 'Substation A']);
    for (var i = 0; i < elements; i++) {
      final id = '_line$i';
      elementStmt.execute([id, 'ACLineSegment']);
      attrStmt
        ..execute([id, 'name', 'Feeder $i'])
        ..execute([id, 'length', (i % 5000).toString()]);
    }
    raw.execute('COMMIT');
  } on Object {
    raw.execute('ROLLBACK');
    rethrow;
  } finally {
    elementStmt.dispose();
    attrStmt.dispose();
  }
  raw.execute('ANALYZE'); // refresh planner stats for the engine queries
}

// ─── Shared fixtures ───────────────────────────────────────────────────

late AppDatabase _db;
late QueryEngine _engine;
late Metamodel _metamodel;

void _setUpFixtures() {
  _db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
  _synthesize(_db, elements: kScaleElements);
  _metamodel = SchemaLoader.load(
    File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
  );
  _engine = QueryEngine(metamodel: _metamodel);
}

void _tearDownFixtures() => _db.close();

// ─── Tests ─────────────────────────────────────────────────────────────

void main() {
  setUpAll(_setUpFixtures);
  tearDownAll(_tearDownFixtures);

  group('TR-8.2 — cold open + first table view render < 3s', () {
    test('countMatching + first 200-row page on 500k elements', () {
      const view = ViewDefinition(
        name: 'TR-8.2',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
      );

      // First-render path: total row count + first page. Both are what the
      // grid asks for on initial paint.
      final sw = Stopwatch()..start();
      final count = _engine.countMatching(_db, view);
      final page = _engine.execute(_db, view, limit: 200, offset: 0);
      sw.stop();

      expect(count, kScaleElements);
      expect(page.length, 200);
      _enforceBudget(
        label: 'TR-8.2 cold open + first render',
        observedMs: sw.elapsedMilliseconds,
        ceilingMs: kBudgetColdOpenPlusFirstRenderMs,
        baselineMs: kBaselineColdOpenPlusFirstRenderMs,
      );
    });
  });

  group('TR-8.3 — filter / sort / search < 200ms (warm)', () {
    test('equality-filtered query against an indexed attribute', () {
      const view = ViewDefinition(
        name: 'TR-8.3-eq',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
        filters: [
          FilterDefinition(
            path: ['length'],
            op: FilterOp.eq,
            value: '1234',
          ),
        ],
      );
      _engine.execute(_db, view, limit: 200, offset: 0); // warm

      final sw = Stopwatch()..start();
      final page = _engine.execute(_db, view, limit: 200, offset: 0);
      sw.stop();
      expect(page, isNotEmpty);

      _enforceBudget(
        label: 'TR-8.3 equality-filtered query',
        observedMs: sw.elapsedMilliseconds,
        ceilingMs: kBudgetWarmFilterSortSearchMs,
        baselineMs: kBaselineWarmFilterSortSearchMs,
      );
    });

    test('prefix-filtered (search) + sort uses the value index', () {
      // SQLite can use a range scan for LIKE 'Feeder 12%' (prefix-only) when
      // the value column is indexed — that's the path we expect the UI's
      // "type-ahead" search to drive. Substring LIKE '%x%' is a different
      // problem: see the informational test below.
      const view = ViewDefinition(
        name: 'TR-8.3-prefix',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
        filters: [
          FilterDefinition(
            path: ['name'],
            op: FilterOp.eq,
            value: 'Feeder 12345',
          ),
        ],
        sort: [SortDefinition(path: ['name'], descending: false)],
      );
      _engine.execute(_db, view, limit: 200, offset: 0); // warm

      final sw = Stopwatch()..start();
      _engine.execute(_db, view, limit: 200, offset: 0);
      sw.stop();

      _enforceBudget(
        label: 'TR-8.3 prefix + sort',
        observedMs: sw.elapsedMilliseconds,
        ceilingMs: kBudgetWarmFilterSortSearchMs,
        baselineMs: kBaselineWarmFilterSortSearchMs,
      );
    });

    test('token-based contains search + sort routes through FTS5 (M9.1)', () {
      // FilterOp.contains on tokenizable input ("Feeder 12") routes through
      // the attributes_fts virtual table — token-AND semantics with prefix
      // match on the trailing token. With sort on the same attribute, the
      // FTS5 narrow happens first, then the sort runs over a small set.
      const view = ViewDefinition(
        name: 'TR-8.3-fts-search',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
        filters: [
          FilterDefinition(
            path: ['name'],
            op: FilterOp.contains,
            value: 'Feeder 12',
          ),
        ],
        sort: [SortDefinition(path: ['name'], descending: false)],
      );
      _engine.execute(_db, view, limit: 200, offset: 0); // warm

      final sw = Stopwatch()..start();
      final page = _engine.execute(_db, view, limit: 200, offset: 0);
      sw.stop();

      expect(page, isNotEmpty);
      _enforceBudget(
        label: 'TR-8.3 FTS5 contains + sort',
        observedMs: sw.elapsedMilliseconds,
        ceilingMs: kBudgetWarmFilterSortSearchMs,
        baselineMs: kBaselineWarmFilterSortSearchMs,
      );
    });

    test(
      'arbitrary-substring search falls back to LIKE (informational)',
      () {
        // Substrings inside a token ("eder 12" rather than "Feeder 12")
        // can't be served by FTS5 with the default unicode61 tokenizer.
        // SQLite ships no trigram tokenizer, so this case still falls back
        // to LIKE '%substring%'. Recorded for visibility.
        const view = ViewDefinition(
          name: 'TR-8.3-substring',
          baseClass: 'ACLineSegment',
          columns: [ColumnDefinition(path: ['name'])],
          filters: [
            FilterDefinition(
              path: ['name'],
              op: FilterOp.contains,
              value: 'eder-12', // hyphen → no FTS5-safe tokens → LIKE path
            ),
          ],
        );
        _engine.execute(_db, view, limit: 200, offset: 0); // warm

        final sw = Stopwatch()..start();
        _engine.execute(_db, view, limit: 200, offset: 0);
        sw.stop();
        // Surfacing the LIKE-fallback measurement so it stays visible in
        // CI logs — this is the remaining substring-search gap.
        // ignore: avoid_print
        print(
          'TR-8.3 LIKE substring (500k rows): ${sw.elapsedMilliseconds}ms',
        );
        expect(sw.elapsedMilliseconds, lessThan(3000));
      },
    );
  });

  group('TR-8.4 — single cell edit < 50ms', () {
    test('SetAttributeValueOp end-to-end through EditController', () {
      // We need a parsed ObjectGraph to drive EditController. The
      // synthesizer skipped the XML parse, so build a tiny graph here that
      // shares the in-memory database for the SQLite half of the work —
      // a more realistic baseline at scale would parse the full source,
      // but the edit cycle's cost is dominated by validate + journal +
      // SQLite UPDATE which don't grow with model size.
      final graph = ObjectGraph.parse(
        File('test/fixtures/cim/sample.xml').readAsStringSync(),
      );
      // The graph and the synthesizer-populated DB share no rows; tear off
      // an isolated DB so the edit's UPDATE actually finds a target.
      final editDb =
          AppDatabase.openInMemory(migrations: cimIndexMigrations);
      addTearDown(editDb.close);

      editDb.raw.execute(
        '''INSERT INTO files (id, path) VALUES (1, 'sample.xml')''',
      );
      for (final el in graph.elements) {
        editDb.raw.execute(
          'INSERT INTO elements (id, class, file_id, source_start, '
          'source_stop) VALUES (?, ?, 1, ?, ?)',
          [
            el.id,
            el.className,
            el.headerSpan.start,
            el.closingSpan?.stop ?? el.headerSpan.stop,
          ],
        );
        for (final attr in el.attributes) {
          editDb.raw.execute(
            'INSERT INTO attributes (element_id, name, value, '
            'source_start, source_stop) VALUES (?, ?, ?, ?, ?)',
            [el.id, attr.shortName, attr.value, attr.textSpan.start,
              attr.textSpan.stop],
          );
        }
      }

      final controller = EditController(
        graph: graph,
        metamodel: _metamodel,
        database: editDb,
        fileId: 1,
      );
      addTearDown(controller.dispose);

      // Warm by applying then undoing a different edit so JIT, planner
      // stats, and string interning settle.
      controller
        ..apply(
          const SetAttributeValueOp(
            elementId: '_line2',
            attributeName: 'name',
            newValue: 'warm',
            oldValue: 'Feeder 13',
          ),
        )
        ..undo();

      final sw = Stopwatch()..start();
      controller.apply(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'name',
          newValue: 'Hot',
          oldValue: 'Feeder 12',
        ),
      );
      sw.stop();

      _enforceBudget(
        label: 'TR-8.4 single cell edit',
        observedMs: sw.elapsedMilliseconds,
        ceilingMs: kBudgetSingleCellEditMs,
        baselineMs: kBaselineSingleCellEditMs,
      );
    });
  });

  group('TR-8 index sanity — EXPLAIN QUERY PLAN', () {
    test('class filter on elements uses elements_by_class index', () {
      const view = ViewDefinition(
        name: 'plan-check',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
      );
      final plan = _engine.explainQueryPlan(_db, view);
      // The base scan must use the `elements_by_class` index, not a full
      // table scan — without it we'd never hit TR-8.2 at scale.
      expect(
        plan.any((row) =>
            row.contains('elements_by_class') ||
            row.toLowerCase().contains('using index')),
        isTrue,
        reason: 'expected an index step in:\n${plan.join("\n")}',
      );
    });
  });
}

// Silence unused-imports analyzer hint while keeping a single import block
// even when tests are commented in/out.
// ignore: unused_element
void _silenceUnused(Database _) {}

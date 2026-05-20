# CIM Forge — Technical Requirements

Technical decisions and constraints supporting `functional-requirements.md`.
Each requirement references the functional requirement(s) it serves.

---

## TR-1: Platform & Stack

- **TR-1.1** Application framework: **Flutter** (desktop), targeting **Windows** and
  **Linux**. (FR-9.1)
- **TR-1.2** Language: **Dart**. Native interop via FFI where required (Git).
- **TR-1.3** Repo name `cim-forge`; Flutter package name `cim_forge`.
- **TR-1.4** Development environment is **Windows** using **PowerShell**.
- **TR-1.5** Minimize external dependencies; prefer well-established, long-term
  supported packages. Every third-party package must be justified.

## TR-2: Architecture

- **TR-2.1** **Vertical Slice Architecture** — code organized by feature area, not
  technical layer. No single file handles more than one responsibility.
- **TR-2.2** Proposed top-level structure:
  ```
  lib/
    features/
      schema/      # CIM metamodel loader, class/attribute lookup
      model/       # RDF/XML parse, typed object graph, SQLite index
      views/       # Table-view definitions, query engine
      grid/        # Spreadsheet-like editor widget + virtualization
      editing/     # Edit journal, batch ops, undo/redo
      xml_patch/   # Surgical XML patching + normalize
      git/         # libgit2 wrapper: commit/branch/fork/push/diff
      diff/        # Text diff (XML) + semantic diff (rows/cells)
    shared/
      rdf/         # Low-level RDF/XML reader/writer primitives
      storage/     # SQLite open/migrate/query helpers
      telemetry/   # Tracing/metrics
  ```
- **TR-2.3** Each feature folder follows a model / context / hook / widget split:
  pure data structures and transformations live in `model/`, not in widget files.
- **TR-2.4** **Rule of 300/500** — components over 300 lines extract logic into hooks;
  over 500 lines they must be decomposed into sub-components.
- **TR-2.5** Heavy data mapping (API/XML responses → display formats) lives in `model/`
  pure functions, never in widget files.

## TR-3: CIM Schema Layer (FA-1)

- **TR-3.1** Parse CIM schema from **RDFS/OWL**; build an in-memory metamodel of
  classes, attributes, associations, enumerations, and inheritance edges.
- **TR-3.2** The metamodel must be **profile-agnostic** — no profile-specific class
  names compiled into the application. (FR-1.2)
- **TR-3.3** Resolve inherited attributes and association endpoints transitively so
  table views can offer them as columns. (FR-1.3, FR-2.2)
- **TR-3.4** The project records its schema identifier/version; schema files travel
  in-repo with the model. (FR-1.4)

## TR-4: Model Layer & Indexing (FA-2, FA-3, FA-8)

- **TR-4.1** Parse CIM **RDF/XML** with a streaming parser to bound memory on large
  files. Build a **typed object graph keyed by `rdf:ID`**.
- **TR-4.2** Maintain a persistent **SQLite index** alongside the model — per-class
  tables (or a typed triple store) enabling fast filtered/sorted table-view queries
  without rescanning XML. SQLite is the indexing mechanism; in-memory structures alone
  are not sufficient at target scale.
- **TR-4.3** The parser must capture **source positions (byte/line ranges)** for every
  element and attribute, to anchor surgical XML patches. Selection of the XML library
  is gated on this capability — see TR-9.1.
- **TR-4.4** Handle RDF/XML reference forms (`rdf:ID`, `rdf:about`, `rdf:resource`,
  nested vs. flattened) and namespace prefixes correctly on both read and write.
- **TR-4.5** Index build and incremental update must run off the UI isolate; progress
  is reported to the UI. (FR-8.2)

## TR-5: View Definition & Query Engine (FA-2)

- **TR-5.1** Table view definitions are serialized as JSON and stored in-repo
  (e.g. `.cimviews/`) so they are versioned with the data. (FR-2.4)
- **TR-5.2** A query engine translates a view definition (base class + columns +
  joins + filters + sort) into SQLite queries against the index.
- **TR-5.3** Derived/joined columns traversing associations must be expressible in the
  view definition and resolvable by the query engine. (FR-2.2)
- **TR-5.4** The view definition schema and query engine must support **composite
  views**: 1-1 inclusions resolve to a single join; 1-n inclusions resolve to a
  bounded, ordered expansion (fixed column-group count, ordered by a user-selected
  attribute of the related child class) producing one row per base element. The
  query engine must detect and report 1-n overflow beyond the configured count.
  (FR-2.7–FR-2.11)
- **TR-5.5** Writes through composite-view columns must route each cell back to the
  correct underlying element (base or included related element) via the edit journal,
  including create/delete of related elements where the view permits. (FR-2.12)

## TR-6: Editing & XML Round-Trip (FA-3, FA-4)

- **TR-6.1** Edits are recorded in an **edit journal** (ordered operation log) that is
  the single source of truth for undo/redo. (FR-3.6)
- **TR-6.2** Each journal operation is applied immediately to the in-memory graph and
  the SQLite index, and accumulated as a **pending XML patch**.
- **TR-6.3** **Hybrid XML strategy**: surgical, position-anchored patches by default
  (FR-4.2); a user-triggered **Normalize** performs canonical reserialization of a file
  (FR-4.3).
- **TR-6.4** Edits are validated against the metamodel (type, cardinality, enumeration
  membership) before being committed to the journal. (FR-3.7)
- **TR-6.5** Batch edits are expressed as a set of journal operations applied
  atomically with a single undo step. (FR-3.2)

## TR-7: Git Layer (FA-5, FA-6)

- **TR-7.1** Git operations use **libgit2** via Dart FFI bindings (e.g.
  `libgit2dart` / `git2dart`) rather than shelling out to a `git` executable.
- **TR-7.2** Availability of **precompiled libgit2 binaries for Windows and Linux**
  must be verified; if unavailable, a build/bundling strategy is required before this
  layer is committed to. This is the primary portability risk — see TR-9.2.
- **TR-7.3** Supported operations: open/init, stage, commit, branch, checkout, clone
  (fork), fetch, pull, push, log, diff. (FR-5.1–FR-5.6)
- **TR-7.4** Remote credentials (token/SSH) are stored via the OS secret store, never
  in the repository or in plaintext config. (FR-5.7)
- **TR-7.5** XML diff is text-level over file content; **semantic diff** is computed by
  diffing the parsed object graphs of two revisions and projecting changes through
  table-view definitions. (FR-6.1, FR-6.2)

## TR-8: Performance Budgets (FA-8)

- **TR-8.1** Target model scale: hundreds of thousands of CIM elements.
- **TR-8.2** Open model + first table view render: target < 3 s for a large model
  (warm SQLite index); index (re)build may take longer but must show progress.
- **TR-8.3** Filter/sort/search within a table view: target < 200 ms against the
  SQLite index.
- **TR-8.4** Single cell edit (journal + in-memory + index update): target < 50 ms.
- **TR-8.5** The grid must be **virtualized** — only visible rows/cells are built.
- **TR-8.6** If a change increases a baseline budget by > 15%, it must be justified or
  optimized.

## TR-9: Key Risks & Required Spikes

- **TR-9.1** **XML source-position fidelity** — confirm a Dart XML library exposes
  byte/line ranges sufficient for surgical patching, or plan a custom reader.
  Time-boxed spike required before the `xml_patch` feature is built. (TR-4.3)
- **TR-9.2** **libgit2 on Windows/Linux** — confirm precompiled binaries or a viable
  build path. Time-boxed spike required before the `git` feature is built. (TR-7.2)
- **TR-9.3** **Spreadsheet grid widget** — no mature Flutter package is known to
  deliver Excel-class editing at the target row count. Expect a custom virtualized
  grid built on Flutter's two-dimensional scrollables; evaluate existing packages as a
  stopgap only.

## TR-10: Observability

- **TR-10.1** Significant operations (parse, index build, query, patch, commit) are
  wrapped in named spans; structured logs include context such as `model_id`,
  `view_id`, `element_id`.
- **TR-10.2** Performance signatures for the budgets in TR-8 are measurable from
  telemetry.

## TR-11: Testing

- **TR-11.1** Follow **Test-Driven Development**.
- **TR-11.2** All verified functionality is memorialized as unit or integration tests;
  no ad-hoc command-line/script testing in place of a preserved test.
- **TR-11.3** Critical round-trip property: parse → edit → patch → reparse must yield
  an equivalent object graph; covered by tests.
- **TR-11.4** UI flows covered by Flutter integration tests; changes must not break
  existing tests, and unclear behavior changes are confirmed with an implementation
  plan before proceeding.

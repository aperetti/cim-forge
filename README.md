# CIM Forge

A desktop application for utility engineers and GIS analysts to build and
maintain **CIM (Common Information Model)** data through custom,
spreadsheet-like table views that are natively backed by **Git** and **CIM
RDF/XML**.

You edit the model in familiar grid views; CIM Forge writes **surgical
patches** back to the underlying RDF/XML so Git diffs stay small and
reviewable, and commits/branches/diffs are first-class operations inside the
app.

> Status: early development (`0.1.0`). The full milestone plan (M0–M9 plus
> follow-ups) is implemented and green — see [Milestones](#milestones) — but
> the app has not had a UX polish pass or a tagged release yet.

---

## Why this exists

CIM models are large RDF/XML files. The CIM ecosystem (CIMTool, CGMES tools,
utility GIS exports) reads and writes RDF/XML, so that stays the source of
truth. But editing raw XML by hand is miserable, and naive "load → mutate →
reserialize" rewrites the whole file, producing enormous, unreviewable Git
diffs.

CIM Forge gives you:

- **Spreadsheet-like editing** over any CIM class, with columns drawn from
  the class's own attributes, inherited attributes, and attributes reached
  through associations (joined / composite views).
- **Surgical XML patches** — an edit to one cell changes one or two lines of
  the file, so `git diff` stays human-readable.
- **Git built in** — commit, branch, view history, text + semantic diffs,
  clone / pull / push, merge-conflict surfacing at the element level.
- **Profile-agnostic** — no CIM profile or class names are compiled in; the
  app adapts to whatever RDFS/OWL schema you load.

See [`functional-requirements.md`](functional-requirements.md) and
[`technical-requirements.md`](technical-requirements.md) for the full spec.

---

## Architecture

- **Flutter desktop** (Windows + Linux), Dart, native interop via FFI for
  Git.
- **Vertical-slice architecture** — code is organized by feature, not by
  technical layer:

  ```
  lib/
    features/
      schema/     # RDFS/OWL → in-memory metamodel (profile-agnostic)
      model/      # RDF/XML parse → typed object graph + SQLite indexer
      views/      # table-view definitions, query engine, CSV export
      grid/       # custom virtualized spreadsheet widget
      editing/    # edit journal, validation, undo/redo, surgical patches
      xml_patch/  # offset-based patcher + canonical (normalize) serializer
      git/        # libgit2 wrapper, credential store, Git side panel
      diff/       # semantic diff + view-projected review + text diff view
      project/    # project lifecycle, on-disk layout, open-project shell
      settings/   # recent projects, window geometry
    shared/
      rdf/        # low-level position-aware RDF/XML event reader
      storage/    # SQLite open/migrate primitives
      telemetry/  # named spans + structured logging
  ```

- **SQLite triple-store index** — the model is indexed into generic
  `elements` / `attributes` / `associations` tables (plus an FTS5 mirror for
  search). This index is a **per-clone cache, not committed** — it's rebuilt
  from the XML on demand. Table-view queries hit the index, not the XML.
- **libgit2 via `git2dart`** — Git operations are FFI calls, not shell-outs.

### How a model lives on disk

A CIM Forge project is a Git repository. Inside it:

| Path | Committed? | What |
|------|------------|------|
| your CIM `*.xml` files | yes | the model — the source of truth |
| `.cimviews/<name>.json` | yes | table-view definitions, shared with the team |
| `.cimforge/project.json` | yes | project marker: schema id, format version |
| `.cimforge/index.sqlite3` | **no** (gitignored) | per-clone query index, rebuilt from XML |

The SQLite index is treated like `node_modules` / `build/`: a derived
artifact you rebuild, never a thing you ship. Committing it would turn every
cell edit into a multi-megabyte binary diff and defeat the whole
surgical-patch design.

---

## Getting started (development)

### Prerequisites

- **Flutter 3.35.7 stable** (matches CI). `flutter --version` to check.
- **Windows:** the prebuilt `libgit2.dll` (shipped by `git2dart_binaries`)
  needs **OpenSSL 3** at runtime (`libcrypto-3-x64.dll`). For dev runs the
  simplest source is **Git for Windows** — make sure
  `C:\Program Files\Git\mingw64\bin` is on your `PATH`. The release installer
  bundles these DLLs itself (see [`packaging/windows/`](packaging/windows)).
- **Windows:** building/running the Flutter desktop app requires **Developer
  Mode** enabled (Flutter uses symlinks for plugins).
- **Linux:** desktop build deps (`clang cmake ninja-build pkg-config
  libgtk-3-dev liblzma-dev`) plus `libsecret` for credential storage.

### Run

```bash
flutter pub get
flutter run -d windows    # or: -d linux
```

### Test + analyze

```bash
flutter analyze           # strict lints (very_good_analysis)
flutter test              # full suite — currently 248 tests + 1 platform-skip
```

Every milestone ships a **gate test** that pins its core property — e.g. the
grid's virtualization bound, the edit round-trip (`parse → edit → patch →
reparse` graph-equivalence), the surgical-edit minimal-diff check, and the
TR-8 performance budgets at 500k elements.

---

## Performance

Targets (from `technical-requirements.md` §TR-8), verified by
`test/perf/tr8_benchmarks_test.dart` on a synthesized 500k-element fixture:

- Cold open + first table render: **< 3 s** (warm index)
- Filter / sort / token-search: **< 200 ms**
- Single cell edit (journal + in-memory + index): **< 50 ms**
- Grid is virtualized — only visible cells are built, regardless of row count.

Each budget is also guarded against a >15% regression. Indexing runs on a
background isolate so large model loads don't freeze the UI.

---

## Packaging

- **Windows** — Inno Setup recipe + an OpenSSL-bundling script in
  [`packaging/windows/`](packaging/windows).
- **Linux** — format decision (AppImage / deb / Flatpak) is gated on the CI
  `Linux libgit2 smoke` result; the decision tree is in
  [`packaging/linux/README.md`](packaging/linux/README.md).

---

## Milestones

All implemented and green:

| | Milestone |
|---|---|
| M0 | Foundation: project file format, SQLite storage, telemetry |
| M1 | Custom virtualized spreadsheet grid |
| M2 | Read-only schema + typed object graph (with source positions) |
| M3 | SQLite triple-store index + view query engine |
| M4 | Edit journal + surgical XML patch (round-trip property) |
| M5 | Git local ops: commit / branch / log / diff |
| M6 | Composite views (1-n inclusions) + view validation |
| M7 | Semantic diff + review, normalize, CSV export |
| M8 | Remotes + credential store + Windows packaging |
| M9 | Off-isolate indexing + TR-8 benchmark suite |
| M9.1 | FTS5 full-text search |

---

## Known limitations / roadmap

- No UX polish pass yet; the UI is functional, not finished.
- Arbitrary mid-token substring search falls back to a slower scan (FTS5
  covers token / prefix search).
- Linux packaging format is not yet chosen (pending the CI Linux signal).
- The CIM fixtures `ACEP_PSIL.xml` / `IEEE13.xml` (GridAPPS-D / Battelle)
  are used for tests pending a redistribution-license review — see
  `test/fixtures/cim/NOTICES.md`.

---

## Out of scope (initial release)

Web / mobile delivery · real-time multi-user co-editing (collaboration is
through Git) · geospatial map editing · power-system analysis / simulation.

---

## Contributing

This is TDD-first: new functionality lands with a preserved unit or
integration test, and changes must keep `flutter analyze` clean and the
suite green. The round-trip property (`parse → edit → patch → reparse`) is
the load-bearing invariant — don't break it.

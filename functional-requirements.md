# CIM Forge — Functional Requirements

A desktop application for utility engineers and GIS analysts to build and maintain
CIM (Common Information Model) models through custom, spreadsheet-like table views
that are natively backed by Git and CIM RDF/XML.

This document captures **business requirements** only. Technical decisions live in
`technical-requirements.md`. Requirements are grouped by functional area.

---

## FA-1: CIM Schema & Metamodel

- **FR-1.1** The application shall load a CIM schema (RDFS/OWL) describing the
  available classes, attributes, associations, and inheritance hierarchy.
- **FR-1.2** The application shall be **profile-agnostic** — it shall not hardcode a
  specific CIM profile, and shall adapt its available classes/attributes to whatever
  schema is loaded (generic CIM RDF/XML).
- **FR-1.3** The application shall present the class hierarchy to the user for
  browsing, including inherited attributes and association endpoints.
- **FR-1.4** The application shall allow a project to declare which schema version it
  targets, so that a model and its schema travel together in the repository.

## FA-2: Table View Definitions

- **FR-2.1** A user shall be able to define a custom **table view** by selecting a CIM
  class as the view's base.
- **FR-2.2** A table view shall allow the user to choose columns from: the base class's
  own attributes, inherited attributes, and attributes reachable through associations
  (joined/derived columns).
- **FR-2.3** A table view definition shall support persistent filters, sort order, and
  column ordering/width.
- **FR-2.4** Table view definitions shall be **versioned inside the repository** so that
  views are shared and reviewed alongside the model data.
- **FR-2.5** A user shall be able to create, rename, duplicate, and delete table views.
- **FR-2.6** A user shall be able to share/export a table view definition independently
  of the data.

### Composite views

- **FR-2.7** A user shall be able to define a **Composite table view** that synthesizes
  one or more related CIM classes into a single table alongside the base class, so that
  related elements are edited together on one row.
- **FR-2.8** A composite view shall support including a related class through a
  **1-1 (or 1-0..1) association**, where the related element's selected attributes
  appear as additional columns on the base element's row.
- **FR-2.9** A composite view shall support including a related class through a
  **1-n association** by expanding a **predefined, fixed number** of related elements
  into repeated column groups on the base element's row.
- **FR-2.10** For a 1-n inclusion, the view definition shall specify (a) the maximum
  number of related elements to expand into columns and (b) a **user-selected ordering
  attribute of the related (child) class** used to order the related elements
  deterministically across those column groups. The ordering attribute is chosen per
  inclusion from the child class's available attributes — it is not a fixed or
  reserved attribute name.
- **FR-2.11** When the actual number of related elements exceeds the predefined count
  for a 1-n inclusion, the view shall clearly indicate the overflow; when it is fewer,
  the unused column groups shall render as empty.
- **FR-2.12** Editing a cell that originates from an included related class shall
  propagate to that related element and its underlying XML, consistent with FA-4,
  including creating or removing related elements where the view permits it.

## FA-3: Data Editing (Spreadsheet-like)

- **FR-3.1** Within a table view, the user shall be able to edit cell values inline,
  with an Excel-like interaction model (keyboard navigation, copy/paste, fill).
- **FR-3.2** The user shall be able to perform **batch edits** — applying a value or
  transformation across a multi-row selection.
- **FR-3.3** The user shall be able to filter and free-text search within a table view.
- **FR-3.4** The user shall be able to add new CIM elements and delete existing elements
  from within a table view.
- **FR-3.5** The user shall be able to edit association endpoints (relationships between
  elements), not only scalar attributes.
- **FR-3.6** All edits shall support multi-step **undo/redo**.
- **FR-3.7** Edits shall be validated against the schema (type, cardinality, enumerated
  values) with clear inline error feedback; invalid edits shall not silently corrupt
  the model.

## FA-4: XML Synchronization

- **FR-4.1** Every edit made in a table view shall be reflected in the underlying CIM
  RDF/XML file(s).
- **FR-4.2** By default, edits shall be applied as **surgical patches** that preserve
  the original file's formatting, comments, and element ordering, so that Git diffs
  remain small and reviewable.
- **FR-4.3** The user shall be able to trigger a **Normalize** action that reserializes
  a file into a canonical form.
- **FR-4.4** The user shall be able to see which pending edits map to which XML changes
  before committing.
- **FR-4.5** The user shall be able to view the raw XML for any element selected in a
  table view.

## FA-5: Git Operations

- **FR-5.1** A project is a Git repository; the application shall open, and where
  needed initialize, a repository for a CIM model.
- **FR-5.2** The user shall be able to **commit** pending changes with a message,
  staging all or a subset of changes.
- **FR-5.3** The user shall be able to create and switch **branches**.
- **FR-5.4** The user shall be able to **fork** a model (clone a remote and configure
  it for independent work).
- **FR-5.5** The user shall be able to **push** to and **pull/fetch** from a configured
  remote.
- **FR-5.6** The user shall be able to view commit history for the model.
- **FR-5.7** Authentication to remotes shall be supported (token/SSH) without storing
  credentials in plaintext in the repository.

## FA-6: Diff & Review

- **FR-6.1** The application shall provide a **native XML diff** view showing
  text-level changes between two commits (or working tree vs. commit).
- **FR-6.2** The application shall provide a **semantic data diff** view, expressed in
  terms of table views — which elements were added, removed, or modified, and which
  cell values changed.
- **FR-6.3** The user shall be able to review changes per table view before committing.
- **FR-6.4** Merge conflicts shall be surfaced to the user in an understandable form
  (at minimum, which files/elements conflict).

## FA-7: Import / Export

- **FR-7.1** The user shall be able to open an existing CIM RDF/XML model (single file
  or a set of related files) into a project.
- **FR-7.2** The user shall be able to export the current model state as CIM RDF/XML.
- **FR-7.3** The user shall be able to export a table view's data to a tabular format
  (e.g. CSV) for external use.

## FA-8: Performance Expectations (user-facing)

- **FR-8.1** Opening a model and rendering a table view shall feel responsive for
  models with hundreds of thousands of elements.
- **FR-8.2** Editing, filtering, and searching within a table view shall feel
  immediate; large operations shall report progress rather than freezing the UI.
- **FR-8.3** Specific latency budgets are defined in `technical-requirements.md`.

## FA-9: Platforms

- **FR-9.1** The application shall run as a desktop application on **Windows** and
  **Linux**.

---

## Out of Scope (initial release)

- Web or mobile delivery.
- Real-time multi-user co-editing (collaboration happens through Git).
- Geospatial map editing (this tool edits the CIM data model, not GIS geometry layers).
- Power-system analysis / simulation.

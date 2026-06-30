# Doom 3 Editor Suite Roadmap

This document turns the editor vision into an execution plan for UDQuakeTools.

## Goals

- Build a shared editor platform over the existing archive and filesystem stack.
- Ship Doom 3-focused tools first: Decl Browser, PDA Editor, Material Editor, UI Editor.
- Integrate script editing and debugging with the external editor app instead of duplicating that stack.
- Keep Quake-focused tooling as a later expansion track.

## Principles

- Shared core first, feature tools second.
- Keep persistence behind interfaces; avoid hard coupling to one storage backend.
- Prefer reusable UI primitives (tree, inspector, search, command routing).
- Treat preview rendering as platform infrastructure, not per-tool custom code.

## Milestones

### M1: Platform Foundation and Asset Access

Scope:
- Implement virtual filesystem API over loose files and package archives.
- Add deterministic path precedence rules and write transaction support.
- Add asset indexing for decl/material/gui/script discovery.
- Define editor module contract (open/save/dirty/undo/find/diagnostics).

Exit criteria:
- Any tool can resolve, read, and write project assets through one API.
- Asset index is queryable by type, path, and name.
- Shared editor shell is usable by at least one tool.

### M2: Decl Browser and PDA Editor

Scope:
- Implement decl parse/index/query/update services.
- Build Decl Browser with search, filters, source navigation, and save.
- Build PDA editing workflows on top of decl and filesystem services.
- Add regression tests for parse, round-trip edits, and persistence safety.

Exit criteria:
- Decl edits are robust and round-trip cleanly.
- PDA create/edit/delete flows work end-to-end.
- Tooling recovers gracefully from invalid edits and external file changes.

### M3: Script Integration and Debug Bridge

Scope:
- Integrate external script editor (open file, jump to symbol/line, diagnostics handoff).
- Add command bridge for run/debug actions.
- Define debug adapter handshake and mapping between game runtime and editor symbols.

Exit criteria:
- Script editing is launched and controlled via UDQuakeTools integration points.
- Debug sessions can be initiated and observed in the external editor workflow.

### M4: Material Editor with Shared Preview Service

Scope:
- Implement material tree and stage editing UX.
- Build shared render-to-texture preview service with camera/model control.
- Support apply/revert with live refresh and stable behavior across docking/viewports.

Exit criteria:
- Material authoring loop (edit -> preview -> apply/save) is reliable.
- Preview service is reusable by other tools.

### M5: UI Editor and Final Parity Pass

Scope:
- Implement GUI hierarchy browser and property inspector.
- Add event/action wiring workflows and validation.
- Reuse shared preview/service primitives where applicable.
- Close parity gaps with legacy MFC workflows.

Exit criteria:
- UI editing workflows are production-viable for core use cases.
- Legacy tool dependency is no longer required for target workflows.

## Cross-Cutting Workstreams

### A. Core APIs

- VFS interface and adapters
- Asset indexing and invalidation
- Change tracking and save transactions
- Undo/redo command model

### B. Shared UI Toolkit

- Tree view
- Property grid
- Search panel
- Modal and dialog helpers
- Command palette + shortcuts

### C. Validation and Test Harness

- Fixture project with representative Doom 3 data layout
- Round-trip parser tests for decl/material/gui
- Smoke tests for tool startup and open/edit/save cycles
- Platform matrix test definitions (macOS, GNUstep/Linux, Windows later)

## Proposed Issue Backlog (Create as GitHub Issues)

### Epic 1: Virtual Filesystem

1. VFS-001: Define virtual path and mount model
- Deliverables: API contract doc and interface header
- Depends on: none
- Acceptance: mount ordering and precedence rules are explicit and tested

2. VFS-002: Implement loose file + package archive adapters
- Deliverables: adapter implementations over existing archive stack
- Depends on: VFS-001
- Acceptance: read path resolution passes precedence tests

3. VFS-003: Add transactional write API
- Deliverables: safe write/rollback flow
- Depends on: VFS-002
- Acceptance: simulated failure leaves previous asset intact

4. VFS-004: Add file watch/change notifications
- Deliverables: event API and subscription hooks
- Depends on: VFS-002
- Acceptance: external edits trigger reload path deterministically

### Epic 2: Asset Index and Decl Platform

5. DECL-001: Build asset indexer for decl/material/gui/script
- Depends on: VFS-002
- Acceptance: indexed query returns stable metadata and source location

6. DECL-002: Decl parser and structured model
- Depends on: DECL-001
- Acceptance: parser supports lossless round-trip for fixture corpus

7. DECL-003: Decl persistence adapter abstraction
- Depends on: DECL-002
- Acceptance: parser/editor layers are storage-backend-agnostic

8. DECL-004: Decl Browser UI
- Depends on: DECL-001, DECL-002
- Acceptance: search/filter/open/edit/save working with diagnostics

### Epic 3: PDA Tooling

9. PDA-001: PDA domain model and validation rules
- Depends on: DECL-002
- Acceptance: invalid references are reported pre-save

10. PDA-002: PDA editor workflows (CRUD)
- Depends on: PDA-001, DECL-004
- Acceptance: add/delete/edit for pda/email/audio/video paths

11. PDA-003: PDA regression suite
- Depends on: PDA-002
- Acceptance: automated tests cover create/update/delete and reload

### Epic 4: Script Integration

12. SCRIPT-001: External editor bridge (open/jump)
- Depends on: VFS-002
- Acceptance: file and symbol jumps open at expected location

13. SCRIPT-002: Diagnostics and command handoff
- Depends on: SCRIPT-001
- Acceptance: diagnostics and run commands flow through integration API

14. SCRIPT-003: Debug protocol bridge planning spike
- Depends on: SCRIPT-002
- Acceptance: interface spec for breakpoints, stack, locals, watches

### Epic 5: Material Editor

15. MAT-001: Shared preview service API
- Depends on: VFS-002
- Acceptance: one embeddable preview panel renders controlled scene

16. MAT-002: Render-to-texture implementation
- Depends on: MAT-001
- Acceptance: stable orientation, scaling, and docking behavior

17. MAT-003: Material tree and stage editing
- Depends on: DECL-002, MAT-002
- Acceptance: edit/apply/revert/save cycle works on fixture materials

18. MAT-004: Material editor UX and shortcuts
- Depends on: MAT-003
- Acceptance: common workflows reachable via shortcuts and context menus

### Epic 6: UI Editor

19. UI-001: GUI hierarchy model and parser hooks
- Depends on: DECL-001
- Acceptance: hierarchy view is consistent with source data

20. UI-002: Property inspector and bindings
- Depends on: UI-001
- Acceptance: edits validate and persist safely

21. UI-003: UI editor interaction workflows
- Depends on: UI-002
- Acceptance: event/action wiring and preview loop are usable

## Sprint Plan

### Sprint 1

- VFS-001, VFS-002
- DECL-001
- SCRIPT-001

Sprint objective:
- One shared path to discover assets and open script files in the external editor.

### Sprint 2

- VFS-003, VFS-004
- DECL-002, DECL-004
- PDA-001

Sprint objective:
- Decl Browser and core PDA model running on stable filesystem and persistence primitives.

### Sprint 3

- PDA-002, PDA-003
- SCRIPT-002, SCRIPT-003
- MAT-001 (API only)

Sprint objective:
- PDA editor usable in daily workflows and script/debug bridge scoped.

## Risks and Mitigations

1. Preview rendering complexity (material and UI)
- Mitigation: isolate preview as one reusable service with dedicated tests.

2. Data model lock-in from persistence choice
- Mitigation: storage adapter boundary; keep parser/editor model neutral.

3. Scope creep from script feature duplication
- Mitigation: force script work into integration-only tasks.

4. Cross-platform behavior drift
- Mitigation: smoke checks per platform from M2 onward.

## Definition of Done for Each Tool

- Core workflows complete for target use cases.
- Dirty state and undo/redo are reliable.
- Save behavior is crash-safe.
- Automated smoke test exists for open/edit/save.
- Tool state restores correctly on restart.

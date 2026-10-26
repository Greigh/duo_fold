# Changelog

## 0.1.2 - 2026-10-26

- Settled-verdict tracking (`foldSettled` on `DuoFoldState`): the
  provider no longer gates on `isFoldable`, seeds `isDuo` from a cached
  settled verdict or a known-foldable machine id (`iPhone19,4`), and
  holds back unsettled snapshots that would regress a seeded device.
  Settled verdicts persist under `duo_known_foldable`.
- `FoldStartupGate`: holds an app-supplied splash up to 1500ms until
  the fold verdict settles; a seeded Duo opens immediately.
- Flat pose with a missing division band now splits instead of
  dropping to single, and `clippedDivision` synthesises a centred 40pt
  band while the region report lags the hinge. Only a horizontal band
  degrades flat to single.
- Tests ported for the provider (seeding, hold-back, settled
  persistence), the startup gate, and the new layout cases.

## 0.1.1 - 2026-10-25

- Remove the pre-publish checklist from the README (docs only, no code
  changes).

## 0.1.0 - 2026-10-25

- Initial extraction from Sensecast (greighstudios/Sensecast, main).
- Pose derivation (`DuoFoldState`, `DuoPose`), layout model
  (`FoldLayout`, `FoldMode`), Riverpod bridge, settings toggles, split
  view, fold-aware sheets/dialogs/confined routes, edge rail geometry.
- Tests for pose, layout, and split view ported from Sensecast.

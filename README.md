# duo_fold

Fold-aware layout for Apple's iPhone Duo in Flutter, extracted from
[Sensecast](https://sensecast.app) (Greigh Studios). It answers one
question the engine does not: given a hinge posture and the reserved
regions the platform reports, what layout should this screen use, and
which pane does each piece of UI belong in?

## Why this exists

On iOS, `MediaQuery.displayFeatures` stays empty even on Duo hardware:
the engine issue tracking that (flutter/flutter#192515) is still open.
So every fold decision in this package is made from
[package:foldable](https://pub.dev/packages/foldable) data (hinge status,
angle, division and occlusion regions, size classes), mapped into this
package's own model. If the engine ever populates displayFeatures, the
bridge layer is the one place that changes.

## What is in it

- **Pose derivation** (`DuoFoldState`, `DuoPose`): hinge status plus
  division orientation plus angle resolves to closed, flat, book,
  onTable, or propped. The 150 degree on-table threshold is
  simulator-derived, not hardware verified.
- **Layout model** (`FoldLayout`, `FoldMode`): pure functions. Book
  splits vertically, on-table splits horizontally, propped goes to a
  glance presentation (or a horizontal split if glance is off), flat
  with a surviving vertical division keeps the two-pane treatment.
  Splits are gated on a 600pt minimum width and defeated by a compact
  horizontal size class (Split View's 469pt pane).
- **Riverpod bridge** (`duoFoldProvider`, `duoFoldForLayout`): a stream
  of fold states, iOS-gated, with a layout-granularity reader that
  rebuilds on pose, division, occlusion, size class, and hinge status,
  but not on raw hinge-angle ticks during a sweep.
- **Split view** (`FoldSplitView`): primary/secondary panes positioned
  around the clipped division, with RTL mirroring on vertical folds and
  a primary-only fallback when no usable division overlaps the window.
- **Fold-aware modals** (`showFoldAwareSheet`, `showFoldAwareDialog`,
  `foldAwareDialogBuilder`, `FoldConfinedRoute`): sheets, dialogs, and
  pushed routes that confine themselves to one pane and re-confine live
  when the hinge moves while they are open. The fold decision is made
  inside the presented content, never once at show time.
- **Settings toggles** (`duoGlanceEnabledProvider`,
  `duoBookSplitProvider`): glance and book-split switches, persisted in
  SharedPreferences under the same keys Sensecast uses.
- **Edge rail geometry** (`EdgeRailGeometry`): the silhouette math for a
  rail drawn in the outer display's reserved right edge, including the
  status alcove pinch, the 8pt sliver, and the cell slot layout. The
  rail widget itself is app-specific and stays in Sensecast.

## Quick start

Wrap your app in a `ProviderScope`, then read the fold state at layout
granularity:

```dart
final fold = duoFoldForLayout(ref);
final mode = FoldLayout.modeFor(
  fold,
  width: MediaQuery.sizeOf(context).width,
  glanceEnabled: ref.watch(duoGlanceEnabledProvider),
  bookSplitEnabled: ref.watch(duoBookSplitProvider),
  horizontalCompact: fold.horizontalSizeClass == 'compact',
);
```

Split content around the crease:

```dart
FoldSplitView(
  fold: fold,
  mode: mode,
  primary: const PrimaryPane(),
  secondary: const SecondaryPane(),
)
```

Confine a sheet to the active pane instead of letting it straddle the
crease:

```dart
showFoldAwareSheet(
  context: context,
  builder: (context) => const MySheetContent(),
);
```

On non-Duo hardware and non-iOS platforms, everything degrades to a
constant unsupported state and the widgets behave like their stock
equivalents.

## The traps this package already fell into

These are covered in detail in FINDINGS.md (bundled alongside the
package). The short version:

1. **Never gate on region isActive.** Reserved regions lag the hinge
   by about a second, and a division can still read active in the
   update that reports the device fully open. Gate on hinge posture
   (`partiallyOpen`) and treat isActive as diagnostics only.
2. **A flat device can still report a division.** Fully open with a
   surviving vertical band keeps the two-pane treatment in this
   package. That is a deliberate app choice, not a framework default:
   if you bridge regions into displayFeatures yourself, gate the
   division on posture or a flat device will split your dialogs.
3. **Do not rebuild on angle ticks.** A physical sweep emits a stream
   of states that differ only by angle. `layoutSignature` excludes the
   raw angle, so layout rebuilds only when a decision-relevant field
   changes.
4. **Decide modal layout inside the presented content.** The hinge can
   move while a sheet is open. A one-shot provider read at show time
   leaves the sheet straddling the crease after a transition.
5. **Keep the skeleton identical across modes.** Sheets, dialogs, and
   confined routes use the same widget skeleton in split and single
   modes, so open content keeps scroll position, form input, and
   selection through a fold transition instead of remounting.
6. **Prefer reported occlusions over fixed tables for the edge rail.**
   The 178pt fallback alcove is the 170pt status cluster zone plus
   margin, but the cluster grows with Live Activities. Read the
   occlusion rect when the platform reports one.
7. **Compact size class defeats splits.** A Split View pane reports a
   division inside it, but at 469pt wide the panes would be unreadable.
   The compact gate and the 600pt width gate both exist for that reason.
8. **RTL mirrors vertical folds.** The primary pane leads on the
   physical right. Every pane computation in this package mirrors, and
   your content should too.

## Simulator-only caveat

Everything here was verified on the iPhone Duo simulator (iOS 27.1
runtime), not on hardware. In particular, these are unverified on a
physical device: the 150 degree on-table threshold, real hinge-angle
behavior across the sweep, crease occlusion, the under-display camera,
true Split View on the inner display, StandBy, inner-island Live
Activities, and glance auto-present cadence. Do not present this package
as hardware verified. If you test on hardware, the measurements the
community needs most are hinge angles at each pose and whether the
150 degree threshold holds.

## What is deliberately not in the package

- The glance screen itself (route, wakelock, content). `FoldMode.glance`
  tells you when to show one; what it contains is your app's call.
- The weather rail widget and its painters. `EdgeRailGeometry` is the
  portable part; the content is Sensecast-specific.
- Localizations. Sensecast ships English and Spanish Duo strings; this
  package has no UI strings of its own.
- The sheet and dialog widget tests from Sensecast. The pose, layout,
  and split view tests are ported here; the sheet tests (16 widget
  tests covering confinement, RTL, re-confinement, and state retention)
  still live in Sensecast and are the next thing to port.

## Origin and license

Extracted from Sensecast's Duo adaptation on `main` (Greigh Studios),
October 2026, with app-specific code removed: theme tokens replaced
with theme defaults, the settings sync hook dropped, and comments
lightly edited for style. Logic is unchanged. MIT license, copyright
Greigh Studios.

## Before publishing

- Confirm the `duo_fold` name on pub.dev (a web search surfaced no
  existing package under that name, but that is not a registry check).
- Dependency versions are already aligned with Sensecast 1.2.1+122
  (checked against the Mac checkout): `flutter_riverpod` ^3.0.0,
  `shared_preferences` ^2.5.5, `foldable` ^1.0.5. Lint parity, if you
  want it, is `flutter_lints` ^6.0.0; Sensecast's own `sensecast_lints`
  package is local-only and not portable.
- `repository` and `homepage` point at
  https://github.com/Greigh/duo_fold (added 2026-10-25).
- Run `flutter analyze` and `flutter test` on a machine with the
  Flutter SDK. Verified 2026-10-25 on a Mac (Flutter 3.47.7, Homebrew):
  analyze clean, all 27 ported tests passed.

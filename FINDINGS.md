# iPhone Duo in a real Flutter app: findings from Sensecast's adaptation

What Sensecast (Greigh Studios) learned building a complete iPhone Duo
adaptation in Flutter, and what the extracted `duo_fold` package carries
over. Everything here was verified on the iPhone Duo simulator (iOS 27.1
runtime), not on hardware. Where a number comes from the simulator, that
is stated. Where it comes from community reports rather than Sensecast's
own runs, that is stated too.

## 1. What the adaptation is

A Dart/Riverpod layer built on `package:foldable` 1.0.5. There is no
native hinge code in the app: no `UIHinge` in Dart, no foldable code in
`ios/`. The bridge maps foldable snapshots into the app's own model,
and every layout decision flows from that model. The app does not set
foldable's `bridgeMode` anywhere, so there is no double confinement
risk from the framework also publishing display features.

The pieces:

- `duo_fold_state.dart` (core): hinge status, pose derivation, the
  layout signature.
- `fold_layout.dart` (core): pure mode resolution and pane geometry.
- `duo_fold_state.dart` (bridge): Riverpod stream over foldable, plus
  the layout-granularity reader.
- `duo_settings_state.dart`: glance and book-split toggles, persisted
  in SharedPreferences, both default on.
- `fold_split_view.dart`: panes positioned around the clipped division.
- `fold_aware_sheet.dart`: fold-confined sheets, dialogs, and pushed
  routes.
- `duo_edge_rail.dart`: the outer-display ambient rail (weather
  content; only its geometry is in the package).
- `duo_glance_screen.dart`: the propped/tent glance card (route
  `/duo-glance`, wakelock while visible, self-dismiss on pose exit).
- Consumers: home, settings, radar, hazard map, appearance settings,
  onboarding (the Duo rail page is index 4, skipped on non-Duo hardware
  with its index reserved), weather wallpaper settings, paywall.
- Tests: pose, layout, split view, sheet confinement (16 widget tests),
  rail geometry and widget tests, provider tests, rebuild tests,
  safe-area tests, and per-screen fold layout tests. Localizations in
  English and Spanish.

## 2. The traps

### 2.1 Never gate on region isActive

Reserved regions lag the hinge by about a second. A division can still
read active in the update that reports the device fully open. The
adaptation gates on hinge posture (`partiallyOpen`) and keeps
`isActiveRegions` for diagnostics only. The pose test that pins this
down is: partially open with `isActiveRegions: false` still reports
`foldInEffect` true and pose book. If you gate a split on isActive, a
flat device splits your dialogs for a frame, and a folding device waits
a second before splitting.

### 2.2 A flat device can still report a division

Fully open with a surviving vertical band keeps the two-pane treatment
in this adaptation. That is a deliberate app choice, and it is the
right one for an app that already has a two-pane tablet layout. But it
is not a safe framework default: if you bridge regions into
displayFeatures yourself, gate the division on posture, or a flat
device will split dialogs that should span the window.

### 2.3 Do not rebuild on angle ticks

A physical sweep emits a continuous stream of states that differ only
by hinge angle. The adaptation projects every state through
`DuoFoldLayoutSignature`, which deliberately excludes the raw angle:
every angle-dependent layout rule already flows through pose (the 150
degree on-table threshold), so layout rebuilds only when a
decision-relevant field changes. Without this, a sweep rebuilds the
tree every tick.

### 2.4 Decide modal layout inside the presented content, not at show time

The hinge can move while a sheet or dialog is already open. The
October 17 audit caught post-migration modals rendered across the
crease because they had read the fold state once at show time. Every
surface in the adaptation watches the fold stream and reflows live:
an open sheet re-confines when a fold arrives mid-presentation, and an
open dialog re-anchors when the fold ends. The sheet test that pins
this enters text, changes the fold, and asserts the text survives (no
remount).

### 2.5 Keep the widget skeleton identical across modes

Sheets, dialogs, and confined routes use the same skeleton in split
and single modes; only layout parameters move. That is what preserves
scroll position, form input, and selection through a fold transition.
The confined route additionally wraps content in a pane-scoped
MediaQuery (size and padding set to the pane, crease-side inset
zeroed) so pane content reasons about the pane, not the display.

### 2.6 A confined route needs its own ScaffoldMessenger

ScaffoldMessenger fans a SnackBar out to every registered root
Scaffold. With a confined route open, that is the pushed pane's
Scaffold plus the dimmed one beneath the barrier: the audit's "one
snackbar per pane" duplication. The confined route body carries a
route-local ScaffoldMessenger, so toasts stay in the pane that asked
for them. The sheet test asserts exactly one SnackBar, inside the
confined pane.

### 2.7 Compact size class defeats splits, even with a division present

A Split View pane on the inner display reports a division inside it,
but at 469pt wide the panes would be unreadable. Two gates exist for
this: the compact horizontal size class forces single mode, and the
600pt minimum width gate covers windowed resizes that keep the regular
size class. The layout tests pin both: 469pt compact with a division
goes single, and 599pt regular with a division goes single.

### 2.8 Clip the division to the window

A Split View pane can contain only part of the hinge. `clippedDivision`
intersects the reported band with the window and returns null when
nothing usable overlaps; every pane rect is computed from the clipped
band. The layout tests pin the clipped case: a 455.5 to 495.5 band in a
469pt window clips to 455.5 to 469, and a band that misses the window
entirely yields null and a primary-only fallback.

### 2.9 Prefer reported occlusions over fixed tables for the edge rail

The rail's fallback alcove is 178pt: the 170pt status cluster zone
plus margin, with an 8pt sliver threading the alcove and a 28pt
shoulder easing out to the full band. That fallback is a table, and
tables break: the status cluster grows with Live Activities. The rail
tests assert that a reported status occlusion drives the alcove depth,
and the package documents the fallback as a last resort, not the
source of truth. Related community measurement (simulator era, not
Sensecast's own run): `statusBarFrame` reports about 2pt on Duo and is
useless; the system column top sits around 96pt, so rail controls
belong in the lower part of the strip.

### 2.10 A pushed route can leave the fold stream stale

The October 18 audit corrected an October 17 claim that the on-table
pose was simulator-unreachable. It was reachable all along: landscape
device attitude plus a partial hinge produces a horizontal division
reliably. The earlier failure sat under a pushed route whose
subscription pause left the fold stream stale. If a pose looks
unreachable, check whether something between you and the stream paused
first.

### 2.11 RTL mirrors vertical folds everywhere

The primary pane leads on the physical right in RTL: split view,
sheets, dialogs, and confined routes all mirror, and the confined
route zeroes the crease-side padding on the mirrored side. The sheet
tests assert right-pane confinement and right-pane dialog centering in
RTL, not just LTR.

### 2.12 Settings restoration across close and reopen

Book to closed to book returns directly to the split with the
selection restored and no Back tap. Two details make that work: the
auto-push mark is consumed inside the push callback, and route removal
is gated on hinge status not being closed plus a settled still-wide
post-frame recheck, firing only while the tracked route is topmost.

### 2.13 Scroll position survives display migration

A shared PageStorage bucket with shared keys preserves scroll offset
when content migrates between displays. Without it, folding and
unfolding resets every list.

### 2.14 Do not lock orientation on a hinge device

Community finding from the October 25 research round, not Sensecast's
own run: locking orientation on a hinge device makes iOS scale the
app instead of laying it out, and no fold is reported. On the
simulator the lock sticks to the bundle ID until reboot. The inner
display also ignores supported interface orientations, so orientation
is not a tool you can use to control fold layout at all.

### 2.15 Resume is not termination

Background to foreground kept the same process and preserved the
route with its scroll offset. True termination and relaunch gave a
new process and the home route (the nav stack is not persisted, which
is expected), with saved location, model selection, canvas, and Duo
toggles restored. An earlier audit row that claimed to test
termination had actually recorded a same-process resume; the two were
verified separately after that correction.

## 3. Measurements

Simulator geometry, Duo simulator, iOS 27.1 runtime:

| Item | Value |
|---|---|
| Outer display | 466 x 678 pt |
| Inner display | 951 x 669 pt (669 x 951 portrait) |
| Crease band | 40 pt |
| Vertical division | x 455.5 to 495.5, full height |
| Horizontal division | y 455.5 to 495.5, full width |
| Panes | about 455.5 pt each side of the band |
| Duo bar inset (trailing) | 84 pt |
| Status cluster zone (outer) | 170 pt tall (occlusion 382, 0, 466, 170) |
| Rail fallback alcove | 178 pt |
| Rail sliver width | 8 pt |
| Rail shoulder | 28 pt |
| Split View pane | 469 pt, compact size class |
| Minimum split width | 600 pt |
| Single-mode sheet cap | 640 pt |
| On-table bottom pane | 173.5 pt (495.5 to 669) |

Native readings from the audit (simulator, via a temporary debug print
that was removed before the report was written):

| Hinge status | Angle | Division | Derived pose |
|---|---|---|---|
| closed | 0.0 | none reported | closed |
| partiallyOpen | 90.0 | vertical 455.5, 0, 495.5, 669 | book |
| partiallyOpen | 90.0 | horizontal 0, 455.5, 669, 495.5 | propped |
| partiallyOpen | 156.1 | horizontal 0, 455.5, 669, 495.5 | onTable |
| fullyOpen | 180.0 | vertical band may persist | flat (splits if band vertical) |

Pose to mode mapping:

| Pose | Mode (defaults on) |
|---|---|
| closed | single (outer display) |
| book | splitVertical (or single if book split off or width under 600) |
| onTable | splitHorizontal |
| propped | glance (or splitHorizontal if glance off) |
| flat, vertical division | splitVertical |
| flat, no division or horizontal division | single |
| any pose, compact size class | single |

## 4. The October 18 audit: what was verified

Environment: Duo simulator (iOS 27.1), driven with `idb hinge`,
`idb rotation`, `idb ui`, `simctl io` per display (LCD for outer,
LCD-1 for inner), `simctl launch`/`terminate`, and direct
container-plist preference injection. Builds were debug simulator
builds of the working tree, rebuilt after each source change. Store
flows stayed untouched; a local debug entitlement gated all Pro
surface checks, with no store sheet and no charge.

Corrections to the October 17 report: the on-table pose is reachable
(see 2.10); a paywall scroll extent of 58,356pt at 3.2x was measured
against the wrong scrollable and re-measured at about 2,125pt over a
312pt viewport, roughly seven screens, with every control reachable by
ordinary scrolling (no layout defect, no code change); and a
terminate/relaunch row had actually recorded a resume (see 2.15).

Results: home fold layout tests 11/11, settings split/collapse tests
4/4, edge rail tests 13/13 as counted at that time, `flutter analyze`
clean on changed files, and a full quiet suite of 1,678 tests passing.
The rail cycled through all seven styles live on the outer display,
with persistence verified across relaunch. Spanish ran live on both
displays, including book split, and Spanish at 1.7x text scaling on
both displays produced zero exceptions. Loading, error, and retry
states survived fold transitions in injected-state widget tests.

Simulator limitations found in the same pass: fold-close locks the
simulator (outer display stays black until wake/unlock); accessibility
frames on the landscape inner display report a transposed 669x951
space while screenshots are ground truth; the accessibility bridge
action channel died once mid-session; nested split-pane scroll views
ignore synthesised scrolls; `spawn defaults write` targets the global
preferences path, not the app container plist; and Duo Split View,
StandBy, and Live Activities remain undrivable in that environment.

## 5. What is still unverified on hardware

No Flutter app has published hardware hinge or geometry measurements
as of October 25, 2026, and Sensecast is no exception. Open questions,
in the order the community would feel them:

1. Real hinge-angle behavior across the sweep, and whether the 150
   degree on-table threshold holds on hardware.
2. Crease occlusion: how much of the band is actually unusable.
3. The under-display camera and its occlusion shape.
4. True Split View on the inner display.
5. StandBy and inner-island Live Activities behavior.
6. Glance auto-present cadence (when the system shows or hides a
   propped glance UI).
7. VoiceOver traversal across panes.
8. Rail glanceability at arm's length.
9. Wallpaper applied through the Shortcuts hand-off.

## 6. What the package leaves out, and why

- The glance screen: route, wakelock, and content are Sensecast's
  product decisions. `FoldMode.glance` tells you when to show one.
- The rail widget, painters, and weather data mapping: only the
  geometry is portable.
- Localizations: Sensecast's Duo strings (English, Spanish) are app
  copy; the package has no UI strings of its own.
- The sheet tests (16 widget tests) and rail tests: ported structure
  is documented in the package README, but the full files still live
  in Sensecast and are the next port.
- Onboarding Duo page, paywall, and per-screen consumers: integration
  examples, not library code.

## 7. Sources and path notes

- Sensecast repository, `main` branch, Greigh Studios Forgejo. Core
  files: `lib/core/layout/duo_fold_state.dart`,
  `lib/core/layout/fold_layout.dart`,
  `lib/presentation/state/duo_fold_state.dart`,
  `lib/presentation/widgets/fold_split_view.dart`,
  `lib/presentation/widgets/fold_aware_sheet.dart`,
  `lib/presentation/widgets/duo_edge_rail.dart`,
  `lib/presentation/state/duo_settings_state.dart`.
- Audit report (confirmed on `main`):
  `docs/audits/finished/2026-10-18-duo-verification/REPORT_2026-10-18-duo-verification.md`,
  with 27 evidence captures and `fold-native-readings.txt`.
- Path correction: an earlier research round cited the design spec at
  `docs/specs/2026-10-12-iphone-duo-design.md`, and a Forgejo web
  session on October 25 returned 404 for that path and for
  `docs/features/finished/iphone-duo/spec.md`. The spec does exist
  in the local checkout at
  `docs/features/finished/iphone-duo/spec.md` (689 lines, dated
  2026-10-12, status: implemented, shipped in the v1.2.0 line), next
  to `plan.md`. The Forgejo 404 is unexplained: either the local
  checkout is ahead of remote `main`, or the web session looked at a
  stale ref. Worth one `git status` check before citing the remote
  path upstream. This write-up draws on the audit report; the spec's
  content (geometry table, regions lag, never publish into
  displayFeatures) matches it throughout.
- `package:foldable` 1.0.5 (pub.dev), including its changelog note
  that hinge readings remain unverified against hardware.
- Flutter engine: issue #192515 (populate displayFeatures on iOS,
  open) and draft PR #193025 (embedder-side implementation).

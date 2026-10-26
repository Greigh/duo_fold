// iPhone Duo fold state: bridges package:foldable into a Riverpod stream
// of DuoFoldState. Non-foldable devices and platforms emit a constant
// unsupported value once and nothing downstream changes behaviour.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foldable/foldable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'duo_fold_state.dart';

/// Thin wrapper over the foldable plugin so tests can substitute fakes.
/// The machine-id channel is how the provider seeds a Duo on first launch:
/// the app answers `hw.machine` (e.g. `iPhone19,4`) over a method channel.
/// The default channel name is the one Sensecast's AppDelegate answers;
/// pass your own name if your native side registers a different channel,
/// or override [machineIdentifier] outright.
class DuoFoldBridge {
  const DuoFoldBridge({this.deviceChannelName = 'com.weatherapp/device'});

  final String deviceChannelName;

  Future<bool> get isFoldable => Foldable.isFoldable;
  Future<FoldableData> snapshot() => Foldable.snapshot;
  Stream<FoldableData> changes() => Foldable.changes;

  /// Best-effort native machine id (`hw.machine`). Null when the channel
  /// is absent, which is the normal case on non-Duo apps.
  Future<String?> machineIdentifier() async {
    try {
      return await MethodChannel(
        deviceChannelName,
      ).invokeMethod<String>('machineIdentifier');
    } catch (_) {
      return null;
    }
  }
}

/// Machine ids that are certainly foldables, so a first launch can seed
/// `isDuo` before the hinge interaction answers. iPhone Duo reports
/// `iPhone19,4` (AppleDB). A stored verdict always wins over this map: a
/// device that was settled non-foldable once is never re-seeded by it.
const foldableMachineIds = {'iPhone19,4'};

/// Cache key for the last settled verdict. The same key Sensecast uses,
/// so an app migrating from the Sensecast implementation keeps its users'
/// cached verdicts.
const _knownFoldableKey = 'duo_known_foldable';

final duoFoldBridgeProvider = Provider<DuoFoldBridge>(
  (ref) => const DuoFoldBridge(),
);

/// Maps a plugin snapshot into our model. A verdict is settled when the
/// bridge has stopped answering `unknown`: that is the signal the
/// startup gate waits for, and the only verdict the cache persists.
/// FoldableData.unsupported is the settled "not a foldable" answer, not
/// the unsettled one (that const carries supportLevel available).
DuoFoldState duoStateFromFoldable(FoldableData data) {
  final settled = data.capabilities.supportLevel != FoldableSupportLevel.unknown;
  if (!data.capabilities.isFoldable) {
    return DuoFoldState.unsupported(foldSettled: settled);
  }
  final divisions = data.regions
      .where((r) => r.kind == ReservedRegionKind.division)
      .toList();
  return DuoFoldState(
    isDuo: true,
    hingeStatus: switch (data.status) {
      HingeStatus.closed => DuoHingeStatus.closed,
      HingeStatus.partiallyOpen => DuoHingeStatus.partiallyOpen,
      HingeStatus.fullyOpen => DuoHingeStatus.fullyOpen,
      _ => DuoHingeStatus.unknown,
    },
    hingeAngleDeg: data.angleDegrees,
    horizontalSizeClass: data.horizontalSizeClass.name,
    verticalSizeClass: data.verticalSizeClass.name,
    divisionRegion: divisions.isEmpty ? null : divisions.first.bounds,
    isActiveRegions: divisions.isNotEmpty && divisions.first.isActive,
    occlusionRegions: data.regions
        .where((r) => r.kind == ReservedRegionKind.occlusion)
        .map((r) => r.bounds)
        .toList(),
    foldSettled: settled,
  );
}

/// Latest fold state. The native `changes` stream is open-ended, so
/// consumers must read `.value`. `duoFoldProvider.future` waits for the
/// stream's *last* event and would never resolve while the device lives.
///
/// iOS-gated: `foldable` is iOS-only today, but if it ever reports on
/// Android/desktop the Duo-labelled UI would engage untested there.
/// Foldables on other platforms stay `unsupported` until a deliberate
/// cross-platform pass.
///
/// No `isFoldable` pre-gate: the first snapshot can answer while the
/// hinge interaction is still settling, and the plugin stream replays
/// the snapshot, keeps listening while unsettled, and closes only on a
/// settled no-hinge device. Gating on it would return before the real
/// answer arrives.
///
/// Seeding: while unsettled, the provider emits `isDuo: true` (a
/// low-information seed, `foldSettled: false`) for a device with a
/// cached settled verdict or a known-foldable machine id, and holds
/// back unsettled snapshots that would regress it to unsupported
/// until a settled verdict lands. A dead bridge yields a settled
/// unsupported verdict so nothing hangs on it.
final duoFoldProvider = StreamProvider<DuoFoldState>((ref) async* {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    yield const DuoFoldState.unsupported(foldSettled: true);
    return;
  }
  final bridge = ref.watch(duoFoldBridgeProvider);
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_knownFoldableKey);
    var seeded = cached == true;
    if (!seeded && !prefs.containsKey(_knownFoldableKey)) {
      seeded = foldableMachineIds.contains(await bridge.machineIdentifier());
    }
    if (seeded) yield const DuoFoldState(isDuo: true);
    var lastSettled = cached;
    // The plugin stream replays the snapshot, then answers hinge
    // changes. Do not await isFoldable first: on real hardware it
    // returns false while the interaction is still settling.
    await for (final data in bridge.changes()) {
      final state = duoStateFromFoldable(data);
      if (state.foldSettled) {
        lastSettled = state.isDuo;
        prefs.setBool(_knownFoldableKey, state.isDuo).ignore();
      }
      if (seeded && !state.foldSettled && !state.isDuo) continue;
      if (lastSettled != null && lastSettled != state.isDuo) {
        // A regression on settled hardware means the stream is answering
        // from the wrong snapshot: keep the last settled verdict.
        yield DuoFoldState(
          isDuo: lastSettled,
          hingeStatus: state.hingeStatus,
          hingeAngleDeg: state.hingeAngleDeg,
          horizontalSizeClass: state.horizontalSizeClass,
          verticalSizeClass: state.verticalSizeClass,
          divisionRegion: state.divisionRegion,
          occlusionRegions: state.occlusionRegions,
          isActiveRegions: state.isActiveRegions,
          foldSettled: state.foldSettled,
        );
        continue;
      }
      yield state;
    }
  } catch (_) {
    yield const DuoFoldState.unsupported(foldSettled: true);
  }
});

/// Watches the fold state at layout granularity: the calling widget
/// rebuilds when any field a layout decision can read changes (pose,
/// division/occlusion bands, size classes, hinge status) but not on
/// raw hinge-angle ticks inside one pose, which a physical sweep emits
/// continuously (pose carries every angle-derived layout rule). Listeners
/// that need each event keep `ref.listen(duoFoldProvider, …)`.
DuoFoldState duoFoldForLayout(WidgetRef ref) {
  ref.watch(duoFoldProvider.select((a) => a.value?.layoutSignature));
  return ref.read(duoFoldProvider).value ?? const DuoFoldState.unsupported();
}

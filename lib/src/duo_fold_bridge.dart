// iPhone Duo fold state: bridges package:foldable into a Riverpod stream
// of DuoFoldState. Non-foldable devices and platforms emit a constant
// unsupported value once and nothing downstream changes behaviour.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foldable/foldable.dart';

import 'duo_fold_state.dart';

/// Thin wrapper over the foldable plugin so tests can substitute fakes.
class DuoFoldBridge {
  const DuoFoldBridge();

  Future<bool> get isFoldable => Foldable.isFoldable;
  Future<FoldableData> snapshot() => Foldable.snapshot;
  Stream<FoldableData> changes() => Foldable.changes;
}

final duoFoldBridgeProvider = Provider<DuoFoldBridge>(
  (ref) => const DuoFoldBridge(),
);

/// Maps a plugin snapshot into our model.
DuoFoldState duoStateFromFoldable(FoldableData data) {
  if (!data.capabilities.isFoldable) return const DuoFoldState.unsupported();
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
final duoFoldProvider = StreamProvider<DuoFoldState>((ref) async* {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    yield const DuoFoldState.unsupported();
    return;
  }
  final bridge = ref.watch(duoFoldBridgeProvider);
  try {
    if (!await bridge.isFoldable) {
      yield const DuoFoldState.unsupported();
      return;
    }
    yield duoStateFromFoldable(await bridge.snapshot());
    await for (final data in bridge.changes()) {
      yield duoStateFromFoldable(data);
    }
  } catch (_) {
    yield const DuoFoldState.unsupported();
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

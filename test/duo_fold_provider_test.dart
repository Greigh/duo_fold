import 'dart:async' show Completer, TimeoutException;

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeNoDuoBridge extends DuoFoldBridge {
  @override
  Future<bool> get isFoldable async => false;

  @override
  Future<FoldableData> snapshot() async => FoldableData.unsupported;

  // The real stream replays the snapshot, then closes on a settled
  // no-hinge answer.
  @override
  Stream<FoldableData> changes() => Stream.value(FoldableData.unsupported);
}

class FakeDuoBridge extends DuoFoldBridge {
  FakeDuoBridge(this.data);
  final FoldableData data;

  @override
  Future<bool> get isFoldable async => true;

  @override
  Future<FoldableData> snapshot() async => data;

  @override
  Stream<FoldableData> changes() => Stream.value(data);
}

/// Cold-boot race on real hardware: `isFoldable` answers false while the
/// hinge interaction is still settling (supportLevel "unknown"), then the
/// stream later reports the real Duo. The provider must not close on the
/// unsettled answer.
class FakeUnsettledDuoBridge extends DuoFoldBridge {
  FakeUnsettledDuoBridge(this.later, {this.machine});
  final FoldableData later;
  final String? machine;

  @override
  Future<bool> get isFoldable async => false;

  @override
  Future<FoldableData> snapshot() async => unsettledData;

  @override
  Stream<FoldableData> changes() => Stream.fromIterable([unsettledData, later]);

  @override
  Future<String?> machineIdentifier() async => machine;
}

/// What the real stream replays while the hinge interaction settles:
/// APIs present, `isFoldable` still false, `supportLevel: unknown`. It is
/// *not* `FoldableData.unsupported` — that const carries the settled
/// "unsupported" verdict, which the provider may not suppress.
final unsettledData = FoldableData(
  capabilities: const FoldableCapabilities(
    isFoldable: false,
    hingeApiPresent: true,
    regionApiPresent: true,
    supportLevel: FoldableSupportLevel.unknown,
    angleUnitVerified: false,
    strategy: 'test',
  ),
  status: HingeStatus.unknown,
  angleDegrees: null,
  regions: const [],
  displayFeatures: const [],
  horizontalSizeClass: SizeClass.regular,
  verticalSizeClass: SizeClass.regular,
);

FoldableData duoData({
  HingeStatus status = HingeStatus.fullyOpen,
  List<ReservedRegion> regions = const [],
}) => FoldableData(
  capabilities: const FoldableCapabilities(
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    supportLevel: FoldableSupportLevel.available,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: null,
  regions: regions,
  displayFeatures: const [],
  horizontalSizeClass: SizeClass.regular,
  verticalSizeClass: SizeClass.regular,
);

void main() {
  // The fold bridge is iOS-only; pin the host platform so the provider
  // reaches the fake bridge (the test host reports TargetPlatform.android).
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'non-iOS platforms are unsupported even when the bridge is foldable',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer(
        overrides: [
          duoFoldBridgeProvider.overrideWithValue(FakeDuoBridge(duoData())),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(duoFoldProvider, (_, _) {});
      addTearDown(sub.close);
      expect(
        await container.read(duoFoldProvider.future),
        const DuoFoldState.unsupported(),
      );
    },
  );

  test('non-foldable bridge emits unsupported', () async {
    final container = ProviderContainer(
      overrides: [duoFoldBridgeProvider.overrideWithValue(FakeNoDuoBridge())],
    );
    addTearDown(container.dispose);
    final sub = container.listen(duoFoldProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      await container.read(duoFoldProvider.future),
      const DuoFoldState.unsupported(),
    );
  });

  test(
    'maps snapshot: posture, size classes, division + occlusion regions',
    () async {
      final data = duoData(
        status: HingeStatus.partiallyOpen,
        regions: [
          const ReservedRegion(
            kind: ReservedRegionKind.division,
            bounds: Rect.fromLTWH(455.5, 0, 40, 669),
            isActive: true,
          ),
          const ReservedRegion(
            kind: ReservedRegionKind.occlusion,
            bounds: Rect.fromLTWH(867, 0, 84, 120),
            isActive: true,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          duoFoldBridgeProvider.overrideWithValue(FakeDuoBridge(data)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(duoFoldProvider, (_, _) {});
      addTearDown(sub.close);
      final s = await container.read(duoFoldProvider.future);
      expect(s.isDuo, isTrue);
      expect(s.hingeStatus, DuoHingeStatus.partiallyOpen);
      expect(s.horizontalSizeClass, 'regular');
      expect(s.divisionRegion, const Rect.fromLTWH(455.5, 0, 40, 669));
      expect(s.occlusionRegions, [const Rect.fromLTWH(867, 0, 84, 120)]);
      expect(s.foldInEffect, isTrue);
    },
  );

  test('bridge stream errors degrade to unsupported, never throw', () async {
    final container = ProviderContainer(
      overrides: [duoFoldBridgeProvider.overrideWithValue(_ThrowingBridge())],
    );
    addTearDown(container.dispose);
    final sub = container.listen(duoFoldProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      await container.read(duoFoldProvider.future),
      const DuoFoldState.unsupported(),
    );
  });

  test(
    'unsettled cold-boot answer does not lose the later hinge report',
    () async {
      final container = ProviderContainer(
        overrides: [
          duoFoldBridgeProvider.overrideWithValue(
            FakeUnsettledDuoBridge(
              duoData(
                status: HingeStatus.partiallyOpen,
                regions: [
                  const ReservedRegion(
                    kind: ReservedRegionKind.division,
                    bounds: Rect.fromLTWH(455.5, 0, 40, 669),
                    isActive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // .future resolves on the first event; collect both events the
      // stream emits and assert the later real-hinge report lands.
      final states = <DuoFoldState>[];
      final done = Completer<void>();
      final sub = container.listen(duoFoldProvider, (_, next) {
        next.whenData((v) {
          states.add(v);
          if (states.length == 2 && !done.isCompleted) done.complete();
        });
      });
      addTearDown(sub.close);
      try {
        await done.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Under the gated provider the second event never arrives.
      }
      expect(states.first.isDuo, isFalse);
      expect(states.last.isDuo, isTrue);
      expect(states.last.hingeStatus, DuoHingeStatus.partiallyOpen);
    },
  );

  test(
    'cached Duo verdict seeds isDuo and suppresses the unsettled regression',
    () async {
      SharedPreferences.setMockInitialValues({'duo_known_foldable': true});
      final container = ProviderContainer(
        overrides: [
          duoFoldBridgeProvider.overrideWithValue(
            FakeUnsettledDuoBridge(
              duoData(
                status: HingeStatus.partiallyOpen,
                regions: [
                  const ReservedRegion(
                    kind: ReservedRegionKind.division,
                    bounds: Rect.fromLTWH(455.5, 0, 40, 669),
                    isActive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final states = <DuoFoldState>[];
      final done = Completer<void>();
      final sub = container.listen(duoFoldProvider, (_, next) {
        next.whenData((v) {
          states.add(v);
          if (states.length == 2 && !done.isCompleted) done.complete();
        });
      });
      addTearDown(sub.close);
      await done.future.timeout(const Duration(seconds: 5));
      // Seed, then the real report — the unsettled unsupported snapshot
      // in between must never surface as a state.
      expect(states, everyElement(predicate<DuoFoldState>((s) => s.isDuo)));
      expect(states.last.hingeStatus, DuoHingeStatus.partiallyOpen);
      expect(
        states.last.divisionRegion,
        const Rect.fromLTWH(455.5, 0, 40, 669),
      );
    },
  );

  test('a foldable machine id seeds isDuo on the very first launch', () async {
    final container = ProviderContainer(
      overrides: [
        duoFoldBridgeProvider.overrideWithValue(
          FakeUnsettledDuoBridge(
            duoData(status: HingeStatus.fullyOpen),
            machine: 'iPhone19,4',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final states = <DuoFoldState>[];
    final done = Completer<void>();
    final sub = container.listen(duoFoldProvider, (_, next) {
      next.whenData((v) {
        states.add(v);
        if (states.length == 2 && !done.isCompleted) done.complete();
      });
    });
    addTearDown(sub.close);
    await done.future.timeout(const Duration(seconds: 5));
    // No cached verdict existed, yet the model-id seed opened isDuo and
    // the unsettled snapshot never surfaced.
    expect(states, everyElement(predicate<DuoFoldState>((s) => s.isDuo)));
  });

  test('a stored non-foldable verdict wins over the machine-id map', () async {
    SharedPreferences.setMockInitialValues({'duo_known_foldable': false});
    final container = ProviderContainer(
      overrides: [
        duoFoldBridgeProvider.overrideWithValue(
          FakeUnsettledDuoBridge(
            duoData(status: HingeStatus.fullyOpen),
            machine: 'iPhone19,4',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final states = <DuoFoldState>[];
    final done = Completer<void>();
    final sub = container.listen(duoFoldProvider, (_, next) {
      next.whenData((v) {
        states.add(v);
        if (states.length == 2 && !done.isCompleted) done.complete();
      });
    });
    addTearDown(sub.close);
    await done.future.timeout(const Duration(seconds: 5));
    // The cached "not foldable" verdict suppresses the machine seed — the
    // unsettled snapshot is allowed to surface.
    expect(states.first.isDuo, isFalse);
    expect(states.last.isDuo, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('duo_known_foldable'), isTrue);
  });

  test('foldSettled marks the verdict, not the device', () {
    expect(duoStateFromFoldable(unsettledData).foldSettled, isFalse);
    expect(duoStateFromFoldable(duoData()).foldSettled, isTrue);
    expect(duoStateFromFoldable(FoldableData.unsupported).foldSettled, isTrue);
    expect(
      const DuoFoldState(isDuo: true).foldSettled,
      isFalse,
      reason: 'the seed is a hint, not a hardware answer',
    );
  });

  test('settled verdicts persist the foldable flag', () async {
    var container = ProviderContainer(
      overrides: [
        duoFoldBridgeProvider.overrideWithValue(FakeDuoBridge(duoData())),
      ],
    );
    addTearDown(container.dispose);
    var sub = container.listen(duoFoldProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(duoFoldProvider.future);
    await Future<void>.delayed(Duration.zero);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('duo_known_foldable'), isTrue);

    sub.close();
    container.dispose();
    container = ProviderContainer(
      overrides: [duoFoldBridgeProvider.overrideWithValue(FakeNoDuoBridge())],
    );
    addTearDown(container.dispose);
    sub = container.listen(duoFoldProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(duoFoldProvider.future);
    await Future<void>.delayed(Duration.zero);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('duo_known_foldable'), isFalse);
  });

  test('duo settings providers default on and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(duoGlanceEnabledProvider.notifier).loaded;
    await container.read(duoBookSplitProvider.notifier).loaded;
    expect(container.read(duoGlanceEnabledProvider), isTrue);
    expect(container.read(duoBookSplitProvider), isTrue);
    await container.read(duoGlanceEnabledProvider.notifier).set(false);
    expect(container.read(duoGlanceEnabledProvider), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('duo_glance_enabled'), isFalse);
  });
}

class _ThrowingBridge extends DuoFoldBridge {
  @override
  Future<bool> get isFoldable async => true;

  @override
  Future<FoldableData> snapshot() => throw StateError('native gone');

  @override
  Stream<FoldableData> changes() => Stream.error(StateError('native gone'));
}

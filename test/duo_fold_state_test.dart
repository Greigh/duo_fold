import 'package:duo_fold/src/duo_fold_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const verticalDivision = Rect.fromLTWH(455.5, 0, 40, 669);
  const horizontalDivision = Rect.fromLTWH(0, 455.5, 669, 40);

  test('foldInEffect keys off posture, never region isActive', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.partiallyOpen,
      divisionRegion: verticalDivision,
      isActiveRegions: false,
    );
    expect(s.foldInEffect, isTrue);
    expect(s.pose, DuoPose.book);
  });

  test('flat with inactive division region reports flat pose', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      divisionRegion: verticalDivision,
      isActiveRegions: false,
    );
    expect(s.foldInEffect, isFalse);
    expect(s.pose, DuoPose.flat);
  });

  test('closed hinge reports closed pose', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.closed,
    );
    expect(s.pose, DuoPose.closed);
  });

  test('horizontal division at tent angle reports propped', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.partiallyOpen,
      hingeAngleDeg: 90,
      divisionRegion: horizontalDivision,
    );
    expect(s.pose, DuoPose.propped);
  });

  test('horizontal division near flat reports onTable', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.partiallyOpen,
      hingeAngleDeg: 165,
      divisionRegion: horizontalDivision,
    );
    expect(s.pose, DuoPose.onTable);
  });

  test('partially open with no division rect falls back to flat', () {
    const s = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.partiallyOpen,
    );
    expect(s.foldInEffect, isTrue);
    expect(s.pose, DuoPose.flat);
  });

  test('non-Duo is unsupported', () {
    const s = DuoFoldState.unsupported();
    expect(s.isDuo, isFalse);
    expect(s.pose, DuoPose.unsupported);
    expect(s.foldInEffect, isFalse);
  });
}

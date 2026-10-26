import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _book = DuoFoldState(
  isDuo: true,
  hingeStatus: DuoHingeStatus.partiallyOpen,
  divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
);

const _propped = DuoFoldState(
  isDuo: true,
  hingeStatus: DuoHingeStatus.partiallyOpen,
  hingeAngleDeg: 90,
  divisionRegion: Rect.fromLTWH(0, 455.5, 669, 40),
);

const _onTable = DuoFoldState(
  isDuo: true,
  hingeStatus: DuoHingeStatus.partiallyOpen,
  hingeAngleDeg: 165,
  divisionRegion: Rect.fromLTWH(0, 455.5, 669, 40),
);

FoldMode mode(
  DuoFoldState fold, {
  double width = 951,
  bool glanceEnabled = true,
  bool bookSplitEnabled = true,
  bool horizontalCompact = false,
}) => FoldLayout.modeFor(
  fold,
  width: width,
  glanceEnabled: glanceEnabled,
  bookSplitEnabled: bookSplitEnabled,
  horizontalCompact: horizontalCompact,
);

void main() {
  test('non-Duo always single', () {
    expect(mode(const DuoFoldState.unsupported()), FoldMode.single);
  });

  test('book pose + split enabled → splitVertical', () {
    expect(mode(_book), FoldMode.splitVertical);
  });

  test('book pose + split disabled → single', () {
    expect(mode(_book, bookSplitEnabled: false), FoldMode.single);
  });

  test('compact horizontal size class defeats split even with division', () {
    expect(mode(_book, width: 469, horizontalCompact: true), FoldMode.single);
  });

  test('narrow regular-class window defeats a vertical split', () {
    // A windowed resize under ~600pt keeps 'regular' — panes would be
    // unreadably thin, so the width gate keeps it single.
    expect(mode(_book, width: 599), FoldMode.single);
    const flat = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
    );
    expect(mode(flat, width: 599), FoldMode.single);
  });

  test('flat pose + vertical division → splitVertical like book pose', () {
    const flat = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
    );
    expect(mode(flat), FoldMode.splitVertical);
  });

  test('flat pose + split disabled → single', () {
    const flat = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
    );
    expect(mode(flat, bookSplitEnabled: false), FoldMode.single);
  });

  test('flat pose + missing division still splits (band is synthesised)', () {
    // Region reports lag the hinge on real hardware by seconds — a Duo
    // that knows it folds must not flash single while the band resolves.
    const flatNoDivision = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
    );
    expect(mode(flatNoDivision), FoldMode.splitVertical);
    const flatHorizontalDivision = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
      divisionRegion: Rect.fromLTWH(0, 455.5, 951, 40),
    );
    expect(mode(flatHorizontalDivision), FoldMode.single);
  });

  test('onTable pose → splitHorizontal', () {
    expect(mode(_onTable), FoldMode.splitHorizontal);
  });

  test('propped + glance enabled → glance', () {
    expect(mode(_propped), FoldMode.glance);
  });

  test('propped + glance disabled → splitHorizontal', () {
    expect(mode(_propped, glanceEnabled: false), FoldMode.splitHorizontal);
  });

  test('clippedDivision clips a pane-straddling division to the window', () {
    const clipped = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.partiallyOpen,
      divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
    );
    expect(
      FoldLayout.clippedDivision(clipped, const Size(469, 669)),
      const Rect.fromLTWH(455.5, 0, 13.5, 669),
    );
  });

  test('clippedDivision returns null when division misses the window', () {
    expect(FoldLayout.clippedDivision(_book, const Size(200, 669)), isNull);
    expect(
      FoldLayout.clippedDivision(
        const DuoFoldState.unsupported(),
        const Size(951, 669),
      ),
      isNull,
    );
  });

  test('clippedDivision centres a synthesised band on a division-less Duo', () {
    const flatNoDivision = DuoFoldState(
      isDuo: true,
      hingeStatus: DuoHingeStatus.fullyOpen,
    );
    expect(
      FoldLayout.clippedDivision(flatNoDivision, const Size(951, 669)),
      const Rect.fromLTWH(455.5, 0, 40, 669),
    );
  });

  test('bottomChromeInsets docks controls below a horizontal division', () {
    const div = Rect.fromLTWH(0, 455.5, 951, 40);
    final insets = FoldLayout.bottomChromeInsets(
      FoldMode.splitHorizontal,
      div,
      const Size(951, 669),
    );
    expect(insets.top, 495.5);
    expect(insets.left, isNull);
  });

  test('bottomChromeInsets docks controls right of a vertical division', () {
    const div = Rect.fromLTWH(455.5, 0, 40, 669);
    final insets = FoldLayout.bottomChromeInsets(
      FoldMode.splitVertical,
      div,
      const Size(951, 669),
    );
    expect(insets.left, 495.5);
    expect(insets.top, isNull);
  });

  test('bottomChromeInsets is null for non-split modes', () {
    const div = Rect.fromLTWH(0, 455.5, 951, 40);
    expect(
      FoldLayout.bottomChromeInsets(
        FoldMode.single,
        div,
        const Size(951, 669),
      ).top,
      isNull,
    );
    expect(
      FoldLayout.bottomChromeInsets(
        FoldMode.glance,
        div,
        const Size(951, 669),
      ).left,
      isNull,
    );
  });

  test('primary/secondary rects split around the clipped band', () {
    const size = Size(951, 669);
    const div = Rect.fromLTWH(455.5, 0, 40, 669);
    expect(
      FoldLayout.primaryRect(FoldMode.splitVertical, div, size),
      const Rect.fromLTWH(0, 0, 455.5, 669),
    );
    expect(
      FoldLayout.secondaryRect(FoldMode.splitVertical, div, size),
      const Rect.fromLTWH(495.5, 0, 455.5, 669),
    );
    const hdiv = Rect.fromLTWH(0, 455.5, 951, 40);
    expect(
      FoldLayout.primaryRect(FoldMode.splitHorizontal, hdiv, size),
      const Rect.fromLTWH(0, 0, 951, 455.5),
    );
    expect(
      FoldLayout.secondaryRect(FoldMode.splitHorizontal, hdiv, size),
      const Rect.fromLTWH(0, 495.5, 951, 173.5),
    );
  });
}

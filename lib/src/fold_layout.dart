import 'dart:ui' show Offset, Rect, Size;

import 'duo_fold_state.dart';

/// The resolved layout treatment for the current fold state.
enum FoldMode {
  /// One canvas: non-Duo, flat, closed, Split View, or toggled off.
  single,

  /// Left/right panes around a vertical division (book pose).
  splitVertical,

  /// Top/bottom panes around a horizontal division (on-table).
  splitHorizontal,

  /// Glance card presentation (propped + glance enabled).
  glance,
}

/// Pure decisions about fold geometry. Nothing here touches the platform.
/// Every input arrives via [DuoFoldState] and the caller's constraints.
abstract final class FoldLayout {
  /// Narrowest window that may split vertically. Each pane needs about
  /// 280pt of readable content beside the crease. Split View panes usually
  /// defeat splits earlier via `horizontalCompact`; this covers windowed
  /// resizes that keep the regular size class.
  static const double minSplitVerticalWidth = 600;

  /// Resolves the fold mode for [fold] at [width] logical pixels.
  /// [horizontalCompact] is the UIKit horizontal size class being compact
  /// (Split View's 469 lp pane). It defeats splits even when a clipped
  /// division rect still reports inside the pane.
  static FoldMode modeFor(
    DuoFoldState fold, {
    required double width,
    required bool glanceEnabled,
    required bool bookSplitEnabled,
    bool horizontalCompact = false,
  }) {
    if (!fold.isDuo || horizontalCompact) return FoldMode.single;
    final verticalSplit = width >= minSplitVerticalWidth;
    switch (fold.pose) {
      case DuoPose.book:
        return bookSplitEnabled && verticalSplit
            ? FoldMode.splitVertical
            : FoldMode.single;
      case DuoPose.onTable:
        return FoldMode.splitHorizontal;
      case DuoPose.propped:
        return glanceEnabled ? FoldMode.glance : FoldMode.splitHorizontal;
      case DuoPose.flat:
        // Fully open still reports the crease band. Split around it like
        // the book pose so the inner display keeps its two-pane treatment.
        // A missing or horizontal band degrades to a single canvas.
        final division = fold.divisionRegion;
        return bookSplitEnabled &&
                verticalSplit &&
                division != null &&
                division.height > division.width
            ? FoldMode.splitVertical
            : FoldMode.single;
      case DuoPose.unsupported:
      case DuoPose.closed:
        return FoldMode.single;
    }
  }

  /// The division band intersected with the window. A Split View pane can
  /// contain only part of the hinge. Null when nothing usable overlaps.
  static Rect? clippedDivision(DuoFoldState fold, Size windowSize) {
    final division = fold.divisionRegion;
    if (division == null) return null;
    final clipped = division.intersect(Offset.zero & windowSize);
    return clipped.isEmpty ? null : clipped;
  }

  /// The primary (continuity) pane rect for a split around [division].
  static Rect primaryRect(FoldMode mode, Rect division, Size windowSize) {
    final window = Offset.zero & windowSize;
    if (mode == FoldMode.splitVertical) {
      return Rect.fromLTWH(
        0,
        0,
        division.left,
        windowSize.height,
      ).intersect(window);
    }
    return Rect.fromLTWH(
      0,
      0,
      windowSize.width,
      division.top,
    ).intersect(window);
  }

  /// Offsets confining a bottom-docked chrome block to the far side of the
  /// fold: below the division for a horizontal split, right of it for a
  /// vertical one. Null offsets mean "unconstrained on that edge".
  static ({double? top, double? left}) bottomChromeInsets(
    FoldMode mode,
    Rect? division,
    Size windowSize,
  ) {
    if (division == null) return (top: null, left: null);
    return switch (mode) {
      FoldMode.splitHorizontal => (top: division.bottom, left: null),
      FoldMode.splitVertical => (top: null, left: division.right),
      _ => (top: null, left: null),
    };
  }

  /// The secondary pane rect on the far side of [division].
  static Rect secondaryRect(FoldMode mode, Rect division, Size windowSize) {
    final window = Offset.zero & windowSize;
    if (mode == FoldMode.splitVertical) {
      return Rect.fromLTWH(
        division.right,
        0,
        windowSize.width - division.right,
        windowSize.height,
      ).intersect(window);
    }
    return Rect.fromLTWH(
      0,
      division.bottom,
      windowSize.width,
      windowSize.height - division.bottom,
    ).intersect(window);
  }
}

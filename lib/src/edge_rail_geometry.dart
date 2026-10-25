// Edge-anchored silhouette for a rail drawn in the iPhone Duo outer
// display's reserved right edge. The wash hugs the glass edge and bleeds
// inward, except through the status alcove at the top, where the
// camera/clock/wifi cluster draws. There the silhouette pinches to a thin
// edge sliver so the system chrome sits on clean glass: the rail threads
// past the cluster rather than painting behind it.
//
// Adapted from Sensecast's weather rail. Only the geometry survives here:
// the rail widget itself, its painters, and its weather data stay in the
// app. Use this to build your own rail content inside the silhouette.
//
// `alcoveBottom` is the bottom of the status occlusion rect when the
// platform reports one. On the Duo outer display the occlusion runs from
// 0 to 170pt, so [fallbackAlcove] (178) is the zone plus margin. Prefer
// the reported occlusion whenever it exists: the cluster grows with Live
// Activities, and a fixed fallback will eventually be wrong.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

abstract final class EdgeRailGeometry {
  /// How far the wash reaches inward from the glass edge.
  static const double bandFraction = 0.58;

  /// Alcove depth used when the platform reports no status occlusion.
  /// Matches the Duo outer display's 170pt cluster zone plus margin.
  static const double fallbackAlcove = 178;

  /// Width of the edge sliver threading the status alcove. Kept clear of
  /// the cluster's rightmost glyphs (about 11pt off the glass on the Duo).
  static const double sliverWidth = 8;

  /// How far below the alcove the wash takes to flare to full width.
  static const double shoulder = 28;

  /// Detail anchors near the glass edge.
  static const double edgePad = 6;

  /// Cell geometry the widget cells stack on: one glyph-over-value
  /// pair inside a glass capsule, one slot pitch, centred on the status
  /// cluster's axis.
  static const double cellPitch = 72;
  static const double cellIconSize = 20;
  static const double cellIconGap = 6;
  static const double cellPadV = 7;
  static const double cellPadH = 10;

  /// The headline chip is a different beast: a compact horizontal
  /// glyph-beside-value capsule parked inside the diagonal shoulder
  /// under the alcove, where the silhouette is still easing out to the
  /// band. Horizontal because the shoulder is short on both width and
  /// height; tucked there it reads as the status cluster's last row.
  static const double headlineIconSize = 16;
  static const double headlineIconGap = 5;
  static const double headlinePadV = 4;
  static const double headlinePadH = 7;
  static const double headlineEdgeInset = 4;

  /// Spacing defaults. Sensecast used theme tokens here; the package uses
  /// 8 and 4. Tune them to your theme if yours differ.
  static const double spacingSm = 8;
  static const double spacingXs = 4;

  /// The chip's top tucks into the alcove's bottom margin: the
  /// reported zone runs past the cluster's real glyphs, so it lands
  /// inside the shoulder where the band eases out to full width.
  static double headlineChipTop(double alcoveBottom) =>
      alcoveBottom - spacingSm;

  /// Where the sun-path goal marker parks: below the headline cell,
  /// high enough that the fill visibly closes on it as the event
  /// approaches.
  static const double sunMarkerY = 0.40;

  /// The next-rain track spans this fraction of the rail, starting below
  /// the headline cell and keeping its marker clear of the rail's end.
  static const double rainTrackTop = 0.40;
  static const double rainTrackBottom = 0.86;

  /// Width of a status cell: most of the strip, so the capsule reads
  /// as chrome rather than a floating chip.
  static double cellWidth(double stripWidth) => stripWidth * 0.84;

  /// Cells centre on the status cluster's axis, which sits left of the
  /// strip's geometric centre. The reserved band extends past the
  /// cluster because the camera eats its top-right corner. Measured
  /// against the clock's centre it lands about 2pt right of the raw
  /// boundary.
  static double cellCenterX(double stripWidth) =>
      stripWidth * (1 - bandFraction) + 2;

  /// First cell slot: right under the status alcove. Close enough to
  /// read as an extension of the OS cluster, far enough to clear the
  /// camera.
  static double firstCellY(double alcoveBottom) => alcoveBottom + spacingXs;

  /// How many cell slots fit between the first slot and the rail's end.
  static int cellsThatFit(double height, double alcoveBottom) => math.max(
    0,
    ((height - edgePad - firstCellY(alcoveBottom)) / cellPitch).floor(),
  );

  /// The hit/semantics rect of slot [index]: the full slot, not just the
  /// painted capsule, so targets are generous and contiguous.
  static Rect cellSlotRect(Size size, double alcoveBottom, int index) =>
      Rect.fromLTWH(
        cellCenterX(size.width) - cellWidth(size.width) / 2,
        firstCellY(alcoveBottom) + index * cellPitch,
        cellWidth(size.width),
        cellPitch,
      );

  /// Inner (left) boundary x at height [y] within a [width]-wide strip.
  /// Through the alcove (y < [alcoveBottom]) only the sliver remains; the
  /// boundary eases out to the full band over [shoulder] points below it.
  static double innerX(double y, double width, double alcoveBottom) {
    final inner = width * (1 - bandFraction);
    final sliver = width - sliverWidth;
    if (y <= alcoveBottom) return sliver;
    if (y >= alcoveBottom + shoulder) return inner;
    final t = (y - alcoveBottom) / shoulder;
    final eased = t * t * (3 - 2 * t);
    return sliver + (inner - sliver) * eased;
  }

  /// The rail silhouette: full height against the glass edge, pinched to
  /// the sliver through the status alcove.
  static Path silhouette(Size size, double alcoveBottom) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height);
    for (double y = size.height; y >= 0; y -= 4) {
      path.lineTo(innerX(y, size.width, alcoveBottom), y);
    }
    return path..close();
  }
}

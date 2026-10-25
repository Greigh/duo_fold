import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Hinge posture as reported by the foldable bridge.
enum DuoHingeStatus { unknown, closed, partiallyOpen, fullyOpen }

/// What the device is physically doing, derived from posture + regions.
enum DuoPose {
  /// Not a foldable / bridge absent.
  unsupported,

  /// Hinge shut: app is on the outer display.
  closed,

  /// Fully open, or a fold we cannot locate. When the crease band is
  /// still reported it splits like [book]; otherwise one canvas.
  flat,

  /// Half-open held like a book: vertical division, left/right panes.
  book,

  /// Half-open lying nearly flat on a table: horizontal division,
  /// hero content above, controls below.
  onTable,

  /// Half-open propped (tent/laptop) at a usable angle: horizontal
  /// division, glance-eligible.
  propped,
}

/// Immutable snapshot of Duo fold state. Everything downstream keys off
/// this; on non-Duo devices it is a constant no-op value.
class DuoFoldState {
  const DuoFoldState({
    required this.isDuo,
    this.hingeStatus = DuoHingeStatus.unknown,
    this.hingeAngleDeg,
    this.horizontalSizeClass,
    this.verticalSizeClass,
    this.divisionRegion,
    this.occlusionRegions = const [],
    this.isActiveRegions = false,
  });

  const DuoFoldState.unsupported()
    : isDuo = false,
      hingeStatus = DuoHingeStatus.unknown,
      hingeAngleDeg = null,
      horizontalSizeClass = null,
      verticalSizeClass = null,
      divisionRegion = null,
      occlusionRegions = const [],
      isActiveRegions = false;

  final bool isDuo;
  final DuoHingeStatus hingeStatus;

  /// Hinge angle in degrees (0 = shut, 180 = flat), when reported.
  final double? hingeAngleDeg;

  /// UIKit horizontal size class name ('compact' | 'regular'), when known.
  final String? horizontalSizeClass;
  final String? verticalSizeClass;

  /// Fold band in window coordinates, when reported (kept even while
  /// inactive: it stays queryable when flat).
  final Rect? divisionRegion;
  final List<Rect> occlusionRegions;

  /// Raw isActive flag for diagnostics: regions lag the hinge about 1 s,
  /// so nothing gates on it.
  final bool isActiveRegions;

  /// Whether a fold is in effect: posture-gated, never isActive-gated.
  bool get foldInEffect => hingeStatus == DuoHingeStatus.partiallyOpen;

  /// Angle at which a horizontal fold counts as lying on a table rather
  /// than propped: at 150 degrees and up the device is nearly flat.
  ///
  /// Simulator-derived threshold, not hardware verified. See README.md.
  static const double _onTableMinAngle = 150;

  DuoPose get pose {
    if (!isDuo) return DuoPose.unsupported;
    switch (hingeStatus) {
      case DuoHingeStatus.closed:
        return DuoPose.closed;
      case DuoHingeStatus.partiallyOpen:
        final division = divisionRegion;
        if (division == null) return DuoPose.flat;
        if (division.height > division.width) return DuoPose.book;
        final angle = hingeAngleDeg;
        if (angle != null && angle >= _onTableMinAngle) {
          return DuoPose.onTable;
        }
        return DuoPose.propped;
      case DuoHingeStatus.fullyOpen:
      case DuoHingeStatus.unknown:
        return DuoPose.flat;
    }
  }

  /// Rebuild-significant projection of this state: see
  /// [DuoFoldLayoutSignature].
  DuoFoldLayoutSignature get layoutSignature => DuoFoldLayoutSignature(
    isDuo: isDuo,
    hingeStatus: hingeStatus,
    pose: pose,
    horizontalSizeClass: horizontalSizeClass,
    verticalSizeClass: verticalSizeClass,
    divisionRegion: divisionRegion,
    occlusionRegions: occlusionRegions,
    isActiveRegions: isActiveRegions,
  );

  @override
  bool operator ==(Object other) =>
      other is DuoFoldState &&
      other.isDuo == isDuo &&
      other.hingeStatus == hingeStatus &&
      other.hingeAngleDeg == hingeAngleDeg &&
      other.horizontalSizeClass == horizontalSizeClass &&
      other.verticalSizeClass == verticalSizeClass &&
      other.divisionRegion == divisionRegion &&
      other.isActiveRegions == isActiveRegions &&
      listEquals(other.occlusionRegions, occlusionRegions);

  @override
  int get hashCode => Object.hash(
    isDuo,
    hingeStatus,
    hingeAngleDeg,
    horizontalSizeClass,
    verticalSizeClass,
    divisionRegion,
    isActiveRegions,
    Object.hashAll(occlusionRegions),
  );
}

/// The fields of a [DuoFoldState] that a layout decision can read.
///
/// The raw hinge angle is deliberately absent. Every angle-dependent
/// layout rule already flows through [DuoFoldState.pose] (the 150 degree
/// on-table threshold lives there), so a physical sweep emits a stream of
/// states that differ only by angle and must not rebuild the tree each
/// tick. Everything else (pose, division, occlusion, size classes,
/// hinge status, Duo-ness) is part of the signature.
class DuoFoldLayoutSignature {
  const DuoFoldLayoutSignature({
    required this.isDuo,
    required this.hingeStatus,
    required this.pose,
    this.horizontalSizeClass,
    this.verticalSizeClass,
    this.divisionRegion,
    this.occlusionRegions = const [],
    this.isActiveRegions = false,
  });

  final bool isDuo;
  final DuoHingeStatus hingeStatus;
  final DuoPose pose;
  final String? horizontalSizeClass;
  final String? verticalSizeClass;
  final Rect? divisionRegion;
  final List<Rect> occlusionRegions;
  final bool isActiveRegions;

  @override
  bool operator ==(Object other) =>
      other is DuoFoldLayoutSignature &&
      other.isDuo == isDuo &&
      other.hingeStatus == hingeStatus &&
      other.pose == pose &&
      other.horizontalSizeClass == horizontalSizeClass &&
      other.verticalSizeClass == verticalSizeClass &&
      other.divisionRegion == divisionRegion &&
      other.isActiveRegions == isActiveRegions &&
      listEquals(other.occlusionRegions, occlusionRegions);

  @override
  int get hashCode => Object.hash(
    isDuo,
    hingeStatus,
    pose,
    horizontalSizeClass,
    verticalSizeClass,
    divisionRegion,
    isActiveRegions,
    Object.hashAll(occlusionRegions),
  );
}

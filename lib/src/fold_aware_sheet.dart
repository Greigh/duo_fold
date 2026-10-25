// Fold-aware modal presentation: when a Duo fold is in effect, bottom
// sheets and dialogs confine themselves to one pane instead of spanning
// the crease. Side-by-side pane confinement is what the fold calls for,
// and it is our own layout code since MediaQuery.displayFeatures stays
// empty on iOS.
//
// The fold decision is made inside the presented content, not at show
// time: the Duo hinge can move while a sheet or dialog is already open
// (the 2026-10-17 audit caught post-migration modals rendered across the
// crease from a one-shot provider read), so each surface watches the fold
// stream and reflows when pose, settings, or window geometry changes.
// The widget skeleton stays the same across modes (only layout
// parameters move), so an open sheet keeps its scroll position, form
// input, and selected state through a fold transition instead of
// remounting.
//
// Adapted from Sensecast: the app theme tokens are replaced with theme
// defaults. Confined cards use the color scheme surface; the default
// sheet radius is 28, matching the value Sensecast used. Override both
// with [backgroundColor] and [shape].

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'duo_fold_bridge.dart';
import 'duo_settings.dart';
import 'fold_layout.dart';

/// Whether [context] sits under a `ProviderScope`. Without one there is
/// no fold stream to watch and every surface degrades to a plain modal.
bool _hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } catch (_) {
    return false;
  }
}

/// The live fold classification for a modal. This is the same decision
/// `FoldSplitView`/`FoldConfinedRoute` make. Sheets and dialogs share it
/// so a modal can never disagree with the split it presents over.
FoldMode _modalFoldMode({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final fold = duoFoldForLayout(ref);
  return FoldLayout.modeFor(
    fold,
    width: MediaQuery.sizeOf(context).width,
    glanceEnabled: ref.watch(duoGlanceEnabledProvider),
    bookSplitEnabled: ref.watch(duoBookSplitProvider),
    horizontalCompact: fold.horizontalSizeClass == 'compact',
  );
}

/// The card a fold-aware sheet paints. The sheet route itself stays
/// transparent so this can move between panes and the free-flowing single
/// presentation without re-creating the route.
class _FoldAwareSheetBody extends ConsumerWidget {
  const _FoldAwareSheetBody({
    required this.builder,
    this.backgroundColor,
    this.shape,
  });

  final WidgetBuilder builder;
  final Color? backgroundColor;
  final ShapeBorder? shape;

  /// Default sheet radius, used when the caller does not restyle the card.
  static const double _defaultSheetRadius = 28;

  /// The stock modal bottom-sheet shape: the framework default when the
  /// caller does not restyle the card.
  static const _defaultSheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(_defaultSheetRadius),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fold = duoFoldForLayout(ref);
    final size = MediaQuery.sizeOf(context);
    final mode = _modalFoldMode(context: context, ref: ref);
    final division = mode == FoldMode.single
        ? null
        : FoldLayout.clippedDivision(fold, size);

    final EdgeInsets edgePad;
    final Alignment alignment;
    final BoxConstraints constraints;
    final Color? color;
    final ShapeBorder? cardShape;
    if (mode == FoldMode.splitVertical && division != null) {
      // The sheet confines to the primary pane: physical left in LTR,
      // physical right in RTL, matching FoldSplitView's pane order.
      edgePad = EdgeInsets.zero;
      alignment = Directionality.of(context) == TextDirection.rtl
          ? Alignment.bottomRight
          : Alignment.bottomLeft;
      constraints = BoxConstraints.tightFor(
        width: FoldLayout.primaryRect(mode, division, size).width,
      );
      color = backgroundColor ?? Theme.of(context).colorScheme.surface;
      cardShape =
          shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_defaultSheetRadius),
            ),
          );
    } else if (mode == FoldMode.splitHorizontal && division != null) {
      // Bottom-pane confinement: the sheet docks below the crease and
      // cannot rise into the hero pane above it.
      edgePad = EdgeInsets.zero;
      alignment = Alignment.bottomCenter;
      constraints = BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: FoldLayout.secondaryRect(mode, division, size).height,
      );
      color = backgroundColor ?? Theme.of(context).colorScheme.surface;
      cardShape = shape ?? _defaultSheetShape;
    } else {
      // No fold split: reproduce the stock modal sheet, centered with
      // the 640 cap the route-level constraint would have applied, inside
      // the same insets useSafeArea produces. The route strips top
      // padding (its useSafeArea: false path), so restore it from
      // viewPadding here.
      final vp = MediaQuery.viewPaddingOf(context);
      edgePad = EdgeInsets.only(top: vp.top, left: vp.left, right: vp.right);
      alignment = Alignment.bottomCenter;
      constraints = BoxConstraints.tightFor(width: math.min(640, size.width));
      final sheetTheme = Theme.of(context).bottomSheetTheme;
      color =
          backgroundColor ??
          sheetTheme.modalBackgroundColor ??
          sheetTheme.backgroundColor;
      cardShape = shape ?? _defaultSheetShape;
    }

    return Padding(
      padding: edgePad,
      child: Align(
        alignment: alignment,
        // Shrink to the card's height so the route can bottom-dock it.
        // A full-height body would cover the whole modal area and make
        // barrier taps above the sheet silently stop dismissing.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: constraints,
          child: Material(
            color: color,
            shape: cardShape,
            child: builder(context),
          ),
        ),
      ),
    );
  }
}

/// Like [showModalBottomSheet], but on a folded Duo the sheet is confined
/// to a pane: the primary pane for a book fold (left in LTR, right in
/// RTL), the bottom pane for a table fold. The confinement is re-evaluated
/// while the sheet is open: a mid-presentation fold transition moves the
/// sheet to the matching pane instead of leaving it across the crease.
Future<T?> showFoldAwareSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool showDragHandle = false,
}) {
  if (!_hasProviderScope(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      shape: shape,
      showDragHandle: showDragHandle,
      // Duo surfaces reserve edge strips (the outer display's curved right
      // edge). Sheet content must clear them like any other system inset.
      useSafeArea: true,
      builder: builder,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    // Always full width: confinement, the 640 cap, and safe-area padding
    // are applied inside the watched sheet body so the layout can react to
    // fold and window changes after the route is already on screen.
    constraints: const BoxConstraints(maxWidth: double.infinity),
    showDragHandle: showDragHandle,
    builder: (ctx) => _FoldAwareSheetBody(
      builder: builder,
      backgroundColor: backgroundColor,
      shape: shape,
    ),
  );
}

/// `showDialog` that anchors the dialog inside the active fold pane. Same
/// fold rules as [showFoldAwareSheet]; outside an active fold it calls
/// [showDialog] untouched.
Future<T?> showFoldAwareDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => foldAwareDialogBuilder(ctx, builder)(ctx),
  );
}

/// A pushed route whose content confines itself to the fold's secondary
/// (detail) pane while a vertical split is in effect. Readable content
/// like search results must not straddle the physical crease. The exposed
/// primary pane keeps the previous route visible under a dismissible
/// barrier, mirroring the split-Settings detail idiom.
///
/// Outside a vertical split (non-Duo, closed, on-table, Split View, or
/// the toggle off) the content fills the window and the route behaves
/// like an ordinary opaque push.
class FoldConfinedRoute<T> extends PageRouteBuilder<T> {
  FoldConfinedRoute({
    required BuildContext context,
    required WidgetBuilder builder,
  }) : super(
         opaque: false,
         barrierDismissible: true,
         barrierColor: Colors.black54,
         barrierLabel: MaterialLocalizations.of(context)
             .modalBarrierDismissLabel,
         pageBuilder: (context, animation, secondaryAnimation) =>
             _FoldConfinedBody(builder: builder),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
             reverseCurve: Curves.easeInCubic,
           );
           return SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.0, 0.05),
               end: Offset.zero,
             ).animate(curved),
             child: FadeTransition(opacity: curved, child: child),
           );
         },
       );
}

class _FoldConfinedBody extends ConsumerWidget {
  const _FoldConfinedBody({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fold = duoFoldForLayout(ref);
    final size = MediaQuery.sizeOf(context);
    final mode = _modalFoldMode(context: context, ref: ref);
    final division = mode == FoldMode.splitVertical
        ? FoldLayout.clippedDivision(fold, size)
        : null;

    // The secondary pane: physical right in LTR, physical left in RTL,
    // where FoldSplitView's mirror places secondary content. When nothing
    // confines the route the pane is simply the whole window. The
    // Stack > Positioned > MediaQuery > Builder skeleton is identical in
    // both shapes so pushed content keeps its state across fold changes.
    final mirrored = Directionality.of(context) == TextDirection.rtl;
    final rect = division == null
        ? (Offset.zero & size)
        : (mirrored
              ? FoldLayout.primaryRect(mode, division, size)
              : FoldLayout.secondaryRect(mode, division, size));
    // Inside the pane the pushed screen sees pane geometry as its whole
    // window: the edge shared with the crease keeps no hardware inset.
    final padding = MediaQuery.paddingOf(context);
    final confinedPadding = division == null
        ? padding
        : (mirrored ? padding.copyWith(right: 0) : padding.copyWith(left: 0));
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: rect.size,
              padding: confinedPadding,
              viewPadding: confinedPadding,
            ),
            // ScaffoldMessenger fans a SnackBar out to every registered root
            // Scaffold. With a confined route open that is the pushed pane's
            // Scaffold plus the dimmed one beneath the barrier (the audit's
            // "one snackbar per pane" dup). A route-local messenger keeps
            // toasts in the pane that asked for them.
            child: ScaffoldMessenger(child: Builder(builder: builder)),
          ),
        ),
      ],
    );
  }
}

/// Wraps a dialog's builder content so it centers inside the primary pane
/// instead of straddling the fold. Pass-through on non-split modes. The
/// pane anchor is re-evaluated on every fold event, so a dialog already
/// on screen follows the device through book, flat, and table poses.
WidgetBuilder foldAwareDialogBuilder(
  BuildContext context,
  WidgetBuilder builder,
) {
  if (!_hasProviderScope(context)) return builder;
  return (ctx) => _FoldAwareDialogBody(builder: builder);
}

class _FoldAwareDialogBody extends ConsumerWidget {
  const _FoldAwareDialogBody({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fold = duoFoldForLayout(ref);
    final size = MediaQuery.sizeOf(context);
    final mode = _modalFoldMode(context: context, ref: ref);
    final division =
        (mode == FoldMode.splitVertical || mode == FoldMode.splitHorizontal)
        ? FoldLayout.clippedDivision(fold, size)
        : null;

    // Same skeleton either way (Align > SizedBox > Center > Builder), so
    // a mid-presentation fold transition repositions the dialog without
    // remounting its contents.
    final pane = division == null
        ? (Offset.zero & size)
        : FoldLayout.primaryRect(mode, division, size);
    final mirrored =
        division != null &&
        mode == FoldMode.splitVertical &&
        Directionality.of(context) == TextDirection.rtl;
    return Align(
      alignment: division == null
          ? Alignment.center
          : (mirrored ? Alignment.topRight : Alignment.topLeft),
      child: SizedBox(
        width: pane.width,
        height: pane.height,
        // The pane becomes the dialog's whole window. MediaQuery-driven
        // sizing inside the dialog reasons about the pane it is confined
        // to, not the display it no longer spans.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: pane.size),
          child: Center(child: builder(context)),
        ),
      ),
    );
  }
}

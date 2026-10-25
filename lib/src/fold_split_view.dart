// Places primary/secondary content on either side of the fold division
// for split modes; degrades to a primary-only when no usable division band
// overlaps the window. In RTL a vertical fold mirrors pane order so the
// primary pane leads on the physical right.

import 'package:flutter/widgets.dart';

import 'duo_fold_state.dart';
import 'fold_layout.dart';

class FoldSplitView extends StatelessWidget {
  const FoldSplitView({
    super.key,
    required this.fold,
    required this.mode,
    required this.primary,
    required this.secondary,
  });

  final DuoFoldState fold;
  final FoldMode mode;
  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    if (mode != FoldMode.splitVertical && mode != FoldMode.splitHorizontal) {
      return primary;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final division = FoldLayout.clippedDivision(fold, size);
        if (division == null) return primary;
        // RTL mirrors reading order across a vertical fold: the leading pane
        // sits on the physical right, matching the Row-based wide layouts.
        final mirrored =
            mode == FoldMode.splitVertical &&
            Directionality.maybeOf(context) == TextDirection.rtl;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: mirrored
                  ? FoldLayout.secondaryRect(mode, division, size)
                  : FoldLayout.primaryRect(mode, division, size),
              child: primary,
            ),
            Positioned.fromRect(
              rect: mirrored
                  ? FoldLayout.primaryRect(mode, division, size)
                  : FoldLayout.secondaryRect(mode, division, size),
              child: secondary,
            ),
          ],
        );
      },
    );
  }
}

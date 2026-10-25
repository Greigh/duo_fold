import 'package:duo_fold/src/duo_fold_state.dart';
import 'package:duo_fold/src/fold_layout.dart';
import 'package:duo_fold/src/fold_split_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _book = DuoFoldState(
  isDuo: true,
  hingeStatus: DuoHingeStatus.partiallyOpen,
  divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
);

Widget wrap(Widget child, {Size size = const Size(951, 669)}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(width: size.width, height: size.height, child: child),
  );
}

void main() {
  testWidgets('splitVertical places panes either side of the division', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        const FoldSplitView(
          fold: _book,
          mode: FoldMode.splitVertical,
          primary: SizedBox.expand(key: Key('primary')),
          secondary: SizedBox.expand(key: Key('secondary')),
        ),
      ),
    );
    final primary = tester.getRect(find.byKey(const Key('primary')));
    final secondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(primary.right, 455.5);
    expect(secondary.left, 495.5);
  });

  testWidgets('single mode renders primary only, secondary absent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(669, 951);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        const FoldSplitView(
          fold: DuoFoldState.unsupported(),
          mode: FoldMode.single,
          primary: SizedBox(key: Key('primary')),
          secondary: SizedBox(key: Key('secondary')),
        ),
        size: const Size(669, 951),
      ),
    );
    expect(find.byKey(const Key('primary')), findsOneWidget);
    expect(find.byKey(const Key('secondary')), findsNothing);
  });

  testWidgets('split with no usable division falls back to primary only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 669);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        const FoldSplitView(
          fold: _book,
          mode: FoldMode.splitVertical,
          primary: SizedBox(key: Key('primary')),
          secondary: SizedBox(key: Key('secondary')),
        ),
        size: const Size(200, 669),
      ),
    );
    expect(find.byKey(const Key('secondary')), findsNothing);
  });
}

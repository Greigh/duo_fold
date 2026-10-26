import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors FoldStartupGate's default hold budget.
const _holdBudget = Duration(milliseconds: 1500);

Widget _host(Stream<DuoFoldState> stream) => ProviderScope(
  overrides: [duoFoldProvider.overrideWith((ref) => stream)],
  child: const MaterialApp(
    home: FoldStartupGate(
      splash: Text('SPLASH'),
      child: Text('HOME'),
    ),
  ),
);

void main() {
  testWidgets('holds the launch surface while the verdict is unsettled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(Stream.value(const DuoFoldState.unsupported())),
    );
    await tester.pump();
    expect(find.text('HOME'), findsNothing);
    // The hold is bounded — it must release on its own.
    await tester.pump(_holdBudget + const Duration(milliseconds: 50));
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a settled verdict releases the gate', (tester) async {
    await tester.pumpWidget(
      _host(Stream.value(const DuoFoldState.unsupported(foldSettled: true))),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a seeded Duo opens immediately, verdict pending or not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(Stream.value(const DuoFoldState(isDuo: true))),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a stream that never answers still times out', (tester) async {
    await tester.pumpWidget(_host(const Stream<DuoFoldState>.empty()));
    await tester.pump();
    expect(find.text('HOME'), findsNothing);
    await tester.pump(_holdBudget + const Duration(milliseconds: 50));
    expect(find.text('HOME'), findsOneWidget);
  });
}

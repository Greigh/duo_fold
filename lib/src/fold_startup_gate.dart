// Holds the launch surface until the fold verdict settles, so the first
// frame never flashes single-pane on a Duo that is still answering.
// A seeded Duo (cached verdict or known-foldable machine id) opens
// immediately; an unsettled non-Duo holds at most [holdBudget], then
// degrades to the previous behaviour (the app's normal first frame).
//
// The app supplies its own [splash]: mirror the native launch screen
// here (same background, same centred mark) so the hand-off is
// invisible. This package ships no splash of its own because a generic
// one would always flash against the app's real launch screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'duo_fold_bridge.dart';

class FoldStartupGate extends ConsumerStatefulWidget {
  const FoldStartupGate({
    super.key,
    required this.child,
    required this.splash,
    this.holdBudget = const Duration(milliseconds: 1500),
  });

  final Widget child;

  /// Launch-screen mirror shown while the verdict is unsettled.
  final Widget splash;

  /// Longest the gate holds before degrading to the normal first frame.
  final Duration holdBudget;

  @override
  ConsumerState<FoldStartupGate> createState() => _FoldStartupGateState();
}

class _FoldStartupGateState extends ConsumerState<FoldStartupGate> {
  Timer? _timer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.holdBudget, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fold = ref.watch(duoFoldProvider).value;
    // A seeded Duo opens immediately; a settled verdict releases the
    // gate; anything else holds until the budget expires.
    final holding =
        !_timedOut && !(fold?.foldSettled ?? false) && !(fold?.isDuo ?? false);
    if (!holding) _timer?.cancel();
    return holding ? widget.splash : widget.child;
  }
}

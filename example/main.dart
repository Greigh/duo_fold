// Minimal demo: pick a pose, see the layout model decide. No Riverpod
// here and no hardware needed: the fold states are built by hand from
// the geometry Sensecast measured on the Duo simulator. In a real app,
// the states come from duoFoldProvider (see README.md).

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DuoFoldDemoApp());

class DuoFoldDemoApp extends StatelessWidget {
  const DuoFoldDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'duo_fold demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const DuoFoldDemoPage(),
    );
  }
}

class DuoFoldDemoPage extends StatefulWidget {
  const DuoFoldDemoPage({super.key});

  @override
  State<DuoFoldDemoPage> createState() => _DuoFoldDemoPageState();
}

class _DuoFoldDemoPageState extends State<DuoFoldDemoPage> {
  DuoPose _pose = DuoPose.book;
  bool _glanceEnabled = true;
  bool _bookSplitEnabled = true;

  DuoFoldState get _fold {
    switch (_pose) {
      case DuoPose.book:
        return const DuoFoldState(
          isDuo: true,
          hingeStatus: DuoHingeStatus.partiallyOpen,
          hingeAngleDeg: 90,
          divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
        );
      case DuoPose.onTable:
        return const DuoFoldState(
          isDuo: true,
          hingeStatus: DuoHingeStatus.partiallyOpen,
          hingeAngleDeg: 165,
          divisionRegion: Rect.fromLTWH(0, 455.5, 669, 40),
        );
      case DuoPose.propped:
        return const DuoFoldState(
          isDuo: true,
          hingeStatus: DuoHingeStatus.partiallyOpen,
          hingeAngleDeg: 90,
          divisionRegion: Rect.fromLTWH(0, 455.5, 669, 40),
        );
      case DuoPose.flat:
        return const DuoFoldState(
          isDuo: true,
          hingeStatus: DuoHingeStatus.fullyOpen,
          hingeAngleDeg: 180,
          divisionRegion: Rect.fromLTWH(455.5, 0, 40, 669),
        );
      case DuoPose.closed:
        return const DuoFoldState(
          isDuo: true,
          hingeStatus: DuoHingeStatus.closed,
          hingeAngleDeg: 0,
        );
      case DuoPose.unsupported:
        return const DuoFoldState.unsupported();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mode = FoldLayout.modeFor(
      _fold,
      width: size.width,
      glanceEnabled: _glanceEnabled,
      bookSplitEnabled: _bookSplitEnabled,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('duo_fold demo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: DuoPose.values.map((pose) {
                return ChoiceChip(
                  label: Text(pose.name),
                  selected: _pose == pose,
                  onSelected: (_) => setState(() => _pose = pose),
                );
              }).toList(),
            ),
          ),
          SwitchListTile(
            title: const Text('Glance enabled'),
            value: _glanceEnabled,
            onChanged: (v) => setState(() => _glanceEnabled = v),
          ),
          SwitchListTile(
            title: const Text('Book split enabled'),
            value: _bookSplitEnabled,
            onChanged: (v) => setState(() => _bookSplitEnabled = v),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'pose: ${_fold.pose.name}  |  mode: ${mode.name}  |  '
              'division: ${_fold.divisionRegion ?? "none"}',
            ),
          ),
          Expanded(
            child: FoldSplitView(
              fold: _fold,
              mode: mode,
              primary: Container(
                color: Colors.teal.shade100,
                alignment: Alignment.center,
                child: const Text('Primary pane'),
              ),
              secondary: Container(
                color: Colors.orange.shade100,
                alignment: Alignment.center,
                child: const Text('Secondary pane'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

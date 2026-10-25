// iPhone Duo user toggles: glance mode in tent pose, fold split layouts.
// Both ship on; they only surface on hardware where isDuo is true.
//
// Persistence is plain SharedPreferences under the same keys Sensecast
// uses, so an app migrating from the Sensecast implementation keeps its
// users' settings. Sensecast also backed these up to its own sync service;
// that hook is intentionally left out here. Watch these providers and sync
// them yourself if your app needs it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DuoGlanceEnabledNotifier extends Notifier<bool> {
  static const _key = 'duo_glance_enabled';

  late Future<void> loaded;

  @override
  bool build() {
    loaded = _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    await loaded;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final duoGlanceEnabledProvider =
    NotifierProvider<DuoGlanceEnabledNotifier, bool>(
      DuoGlanceEnabledNotifier.new,
    );

class DuoBookSplitNotifier extends Notifier<bool> {
  static const _key = 'duo_book_split';

  late Future<void> loaded;

  @override
  bool build() {
    loaded = _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    await loaded;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final duoBookSplitProvider = NotifierProvider<DuoBookSplitNotifier, bool>(
  DuoBookSplitNotifier.new,
);

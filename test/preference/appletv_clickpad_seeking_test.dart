import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an existing enabled switch keeps controls-visible protection',
    () async {
      final prefs = await _prefsWith({'appleTvSeekOnlyWithControls': true});
      expect(
        prefs.get(UserPreferences.appleTvClickpadSeekMode),
        AppleTvClickpadSeekMode.controlsVisible,
      );
    },
  );

  test('an existing disabled switch keeps unrestricted seeking', () async {
    final prefs = await _prefsWith({'appleTvSeekOnlyWithControls': false});
    expect(
      prefs.get(UserPreferences.appleTvClickpadSeekMode),
      AppleTvClickpadSeekMode.always,
    );
  });

  test(
    'migration preserves a new mode and drag distance already chosen',
    () async {
      final prefs = await _prefsWith({
        'appleTvSeekOnlyWithControls': true,
        'appleTvClickpadSeekMode': 'pausedOnly',
        'appleTvClickpadDragThreshold': 96,
      });
      expect(
        prefs.get(UserPreferences.appleTvClickpadSeekMode),
        AppleTvClickpadSeekMode.pausedOnly,
      );
      expect(prefs.get(UserPreferences.appleTvClickpadDragThreshold), 96);
    },
  );

  test('a fresh install keeps the original seeking behaviour', () async {
    final prefs = await _prefsWith({});
    expect(
      prefs.get(UserPreferences.appleTvClickpadSeekMode),
      AppleTvClickpadSeekMode.always,
    );
    expect(prefs.get(UserPreferences.appleTvClickpadDragThreshold), 24);
  });

  test('chosen mode survives recreating preferences after migration', () async {
    final prefs = await _prefsWith({'appleTvSeekOnlyWithControls': true});
    await prefs.set(
      UserPreferences.appleTvClickpadSeekMode,
      AppleTvClickpadSeekMode.pausedOnly,
    );
    await prefs.set(UserPreferences.appleTvClickpadDragThreshold, 48);

    final store = PreferenceStore();
    await store.init();
    final reloaded = UserPreferences(store);
    expect(
      reloaded.get(UserPreferences.appleTvClickpadSeekMode),
      AppleTvClickpadSeekMode.pausedOnly,
    );
    expect(reloaded.get(UserPreferences.appleTvClickpadDragThreshold), 48);
  });
}

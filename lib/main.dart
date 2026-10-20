import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/api_service.dart';
import 'state/app_settings.dart';
import 'state/auth_state.dart';
import 'state/player_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // just_audio has no built-in desktop implementation; media_kit provides it.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    JustAudioMediaKit.ensureInitialized(
      windows: defaultTargetPlatform == TargetPlatform.windows,
      linux: defaultTargetPlatform == TargetPlatform.linux,
    );
  }

  // Enables background playback and lock-screen / notification controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.musicplayer.channel.audio',
    androidNotificationChannelName: '音乐播放',
    androidNotificationOngoing: true,
  );

  final api = ApiService();
  final auth = AuthState(api);
  final player = PlayerState(api);
  final settings = AppSettings();
  // Restore the queue, play mode and playback position from the last session.
  await player.restoreState();
  await settings.load();
  api.onUnauthorized = auth.handleUnauthorized;

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<AuthState>.value(value: auth),
        ChangeNotifierProvider<PlayerState>.value(value: player),
        ChangeNotifierProvider<AppSettings>.value(value: settings),
      ],
      child: const MusicPlayerApp(),
    ),
  );
}


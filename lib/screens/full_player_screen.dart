import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_quality.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/cover_image.dart';
import '../widgets/queue_sheet.dart';

/// Lightweight fade+slide transition; the default platform route animates
/// the whole page (artwork + lyrics) and feels heavy on device.
Route<void> fullPlayerRoute() {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const FullPlayerScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;
  final ScrollController _lyricController = ScrollController();
  Timer? _userScrollTimer;
  bool _userScrolling = false;
  int _lastLyricIndex = -1;
  String? _lastSongKey;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
  }

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _rotation.dispose();
    _lyricController.dispose();
    super.dispose();
  }

  /// Only a real finger drag pauses auto-scroll; programmatic animations
  /// (`animateTo`) also emit scroll notifications, so checking the position
  /// alone used to disable auto-scroll permanently.
  bool _onLyricScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollTimer?.cancel();
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _userScrolling = false;
      });
    }
    return false;
  }

  void _syncRotation(bool playing) {
    if (playing) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else if (_rotation.isAnimating) {
      _rotation.stop();
    }
  }

  void _autoScrollLyrics(PlayerState player) {
    if (_userScrolling) return;
    final index = player.currentLyricIndex;
    if (index < 0 || index >= player.lyrics.length) return;
    if (!_lyricController.hasClients) return;

    const itemExtent = 46.0;
    const topPadding = 72.0;
    final target = topPadding + index * itemExtent + itemExtent / 2;
    final max = _lyricController.position.maxScrollExtent;
    final viewport = _lyricController.position.viewportDimension;
    final offset = (target - viewport / 2).clamp(0.0, max);

    _lyricController.animateTo(
      offset,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the palette (light/dark) changes.
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final song = player.currentSong;

    if (song == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRotation(player.isPlaying);

      // Switching tracks should start the lyric list from the top.
      final songKey = player.currentSong?.uniqueKey;
      if (songKey != _lastSongKey) {
        _lastSongKey = songKey;
        _lastLyricIndex = -1;
        _userScrolling = false;
        if (_lyricController.hasClients) {
          _lyricController.jumpTo(0);
        }
      }

      if (player.currentLyricIndex != _lastLyricIndex) {
        _lastLyricIndex = player.currentLyricIndex;
        _autoScrollLyrics(player);
      }
    });

    final totalMs = player.duration.inMilliseconds;
    final value = _dragValue ??
        (totalMs > 0
            ? (player.position.inMilliseconds.clamp(0, totalMs)).toDouble()
            : 0.0);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dimmed artwork backdrop. A full-screen BackdropFilter used to sit
          // here; it re-blurred the whole page every frame and made the route
          // transition stutter, so a cheap static gradient does the job.
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(url: song.artwork),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: AppColors.isDark
                          ? const [
                              Color(0xE60A0C12),
                              Color(0xF507080C),
                              Color(0xFF07080C),
                            ]
                          : const [
                              Color(0xE6FFFFFF),
                              Color(0xF7FFFFFF),
                              Color(0xFFFFFFFF),
                            ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(context, player),
                const Spacer(flex: 2),
                RepaintBoundary(child: _cover(song.artwork)),
                const SizedBox(height: 26),
                _songInfo(song.title, song.artist, song.album),
                const Spacer(flex: 2),
                Expanded(
                  flex: 5,
                  child: RepaintBoundary(
                    // Rebuild lyrics only when the highlighted line changes,
                    // not on every position tick.
                    child: Selector<PlayerState, (int, int, bool)>(
                      selector: (_, p) => (
                        p.currentLyricIndex,
                        p.lyrics.length,
                        p.lyricsLoading,
                      ),
                      builder: (context, _, __) =>
                          _lyrics(context.read<PlayerState>()),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _progress(player, value, totalMs),
                _controls(context, player),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, PlayerState player) {
    final artist = player.currentSong?.artist ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: 30, color: AppColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '正在播放',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  artist.isEmpty ? '未知歌手' : artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _pickQuality(context, player),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                player.quality.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _pickQuality(BuildContext context, PlayerState player) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.text3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '播放音质',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              for (final option in AudioQuality.values)
                ListTile(
                  leading: Icon(
                    option == player.quality
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 19,
                    color: option == player.quality
                        ? AppColors.accent
                        : AppColors.text3,
                  ),
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: option == player.quality
                          ? AppColors.accent
                          : AppColors.text,
                    ),
                  ),
                  subtitle: Text(
                    option.description,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text2),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    player.setQuality(option);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _cover(String artwork) {
    return RotationTransition(
      turns: _rotation,
      child: Container(
        width: 236,
        height: 236,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.isDark ? const Color(0xFF101218) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.isDark
                  ? const Color(0x99000000)
                  : const Color(0x1F000000),
              blurRadius: 46,
              offset: const Offset(0, 18),
            ),
          ],
          border: Border.all(
            color: AppColors.isDark
                ? const Color(0x1FFFFFFF)
                : const Color(0x14000000),
          ),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverImage(url: artwork, width: 226, height: 226, radius: 113),
              Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.isDark
                        ? const Color(0xFF0B0C11)
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.isDark
                          ? const Color(0x00FFFFFF)
                          : const Color(0x14000000),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songInfo(String title, String artist, String album) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            title.isEmpty ? '未知歌曲' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            album.isEmpty ? artist : '$artist · $album',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _lyrics(PlayerState player) {
    if (player.lyricsLoading) {
      return Center(
        child: Text('歌词加载中...',
            style: TextStyle(fontSize: 12, color: AppColors.text2)),
      );
    }
    if (player.lyrics.isEmpty) {
      return Center(
        child: Text('暂无歌词',
            style: TextStyle(fontSize: 12, color: AppColors.text2)),
      );
    }
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent
        ],
        stops: [0.0, 0.2, 0.8, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onLyricScroll,
        child: ListView.builder(
          controller: _lyricController,
          padding: const EdgeInsets.symmetric(vertical: 72),
          itemExtent: 46,
          itemCount: player.lyrics.length,
          itemBuilder: (context, index) {
            final active = index == player.currentLyricIndex;
            return GestureDetector(
              onTap: () => player.seekToLyric(index),
              child: Center(
                child: Text(
                  player.lyrics[index].text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: active ? 17 : 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active
                        ? AppColors.text
                        : (index < player.currentLyricIndex
                            ? AppColors.text2
                            : AppColors.text3),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _progress(PlayerState player, double value, int totalMs) {
    final max = (totalMs > 0 ? totalMs : 1).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.isDark
                  ? const Color(0x3DFFFFFF)
                  : const Color(0x33000000),
              thumbColor: AppColors.isDark ? Colors.white : AppColors.text,
              overlayColor: AppColors.accent.withValues(alpha: 0.18),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 0,
              max: max,
              value: value.clamp(0, max),
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragValue = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDuration(Duration(milliseconds: value.round())),
                  style: TextStyle(
                      fontSize: 11, color: AppColors.text2),
                ),
                Text(
                  formatDuration(player.duration -
                      Duration(milliseconds: value.round())),
                  style: TextStyle(
                      fontSize: 11, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, PlayerState player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PlainControl(
            icon: player.playMode == PlayMode.order
                ? Icons.repeat_rounded
                : player.playMode == PlayMode.random
                    ? Icons.shuffle_rounded
                    : Icons.repeat_one_rounded,
            active: player.playMode != PlayMode.order,
            onTap: player.togglePlayMode,
          ),
          _PlainControl(
            icon: Icons.skip_previous_rounded,
            iconSize: 34,
            onTap: player.prev,
          ),
          GestureDetector(
            onTap: player.togglePlay,
            child: Container(
              width: 66,
              height: 66,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: kAccentGradient,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66FF4D6D),
                    blurRadius: 26,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: player.isLoadingUrl
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Icon(
                      player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
            ),
          ),
          _PlainControl(
            icon: Icons.skip_next_rounded,
            iconSize: 34,
            onTap: player.next,
          ),
          _PlainControl(
            icon: Icons.queue_music_rounded,
            onTap: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _PlainControl extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double iconSize;
  final VoidCallback onTap;

  const _PlainControl({
    required this.icon,
    this.active = false,
    this.iconSize = 24,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(
          icon,
          size: iconSize,
          color: active ? AppColors.accent : AppColors.text2,
        ),
      ),
    );
  }
}

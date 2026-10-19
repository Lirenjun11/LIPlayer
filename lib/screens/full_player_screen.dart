import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/cover_image.dart';
import '../widgets/queue_sheet.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;
  final ScrollController _lyricController = ScrollController();
  bool _userScrolling = false;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _lyricController.addListener(() {
      if (!_lyricController.hasClients) return;
      final atBottom = _lyricController.position.pixels >=
          _lyricController.position.maxScrollExtent - 8;
      _userScrolling = !atBottom;
    });
  }

  @override
  void dispose() {
    _rotation.dispose();
    _lyricController.dispose();
    super.dispose();
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
    if (player.currentLyricIndex < 0) return;
    const itemExtent = 46.0;
    final target = player.currentLyricIndex * itemExtent;
    if (_lyricController.hasClients) {
      final max = _lyricController.position.maxScrollExtent;
      final viewport = _lyricController.position.viewportDimension;
      final offset = (target - viewport / 2 + itemExtent).clamp(0.0, max);
      _lyricController.animateTo(
        offset,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final song = player.currentSong;

    if (song == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRotation(player.isPlaying);
      _autoScrollLyrics(player);
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
          // Blurred art backdrop.
          CoverImage(url: song.artwork),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: Container(color: const Color(0xC407080C)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x1A000000), Color(0xE607080C)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(context, song.artist),
                const Spacer(flex: 2),
                _cover(song.artwork),
                const SizedBox(height: 26),
                _songInfo(song.title, song.artist, song.album),
                const Spacer(flex: 2),
                Expanded(flex: 5, child: _lyrics(player)),
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

  Widget _topBar(BuildContext context, String artist) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 30, color: AppColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
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
                  style: const TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded,
                size: 24, color: AppColors.text),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
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
          color: const Color(0xFF101218),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 46,
              offset: Offset(0, 18),
            ),
          ],
          border: Border.all(color: const Color(0x1FFFFFFF)),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B0C11),
                    shape: BoxShape.circle,
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
            style: const TextStyle(
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
            style: const TextStyle(fontSize: 12, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _lyrics(PlayerState player) {
    if (player.lyricsLoading) {
      return const Center(
        child: Text('歌词加载中...',
            style: TextStyle(fontSize: 12, color: AppColors.text2)),
      );
    }
    if (player.lyrics.isEmpty) {
      return const Center(
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
                      ? Colors.white
                      : (index < player.currentLyricIndex
                          ? const Color(0xFF8890A0)
                          : const Color(0xFF5D6472)),
                ),
              ),
            ),
          );
        },
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
              inactiveTrackColor: const Color(0x3DFFFFFF),
              thumbColor: Colors.white,
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
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.text2),
                ),
                Text(
                  formatDuration(player.duration -
                      Duration(milliseconds: value.round())),
                  style: const TextStyle(
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

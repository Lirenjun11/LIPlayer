import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/full_player_screen.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import 'cover_image.dart';

/// Floating frosted-glass capsule showing the current track.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild when the palette (light/dark) changes.
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(fullPlayerRoute()),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                // Heavy black shadow looks detached on the light palette.
                color: AppColors.isDark
                    ? const Color(0x8C000000)
                    : const Color(0x1A000000),
                blurRadius: AppColors.isDark ? 20 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.isDark
                      ? const Color(0x99101319)
                      : const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.isDark
                        ? const Color(0x26FFFFFF)
                        : const Color(0x14000000),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: player.progress / 100,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.accent),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 6, 8),
                      child: Row(
                        children: [
                          CoverImage(
                              url: song.artwork,
                              width: 42,
                              height: 42,
                              radius: 12),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title.isEmpty ? '未知歌曲' : song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist.isEmpty ? '未知歌手' : song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.text2),
                                ),
                              ],
                            ),
                          ),
                          _MiniIconButton(
                            icon: player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            loading: player.isLoadingUrl,
                            onTap: player.togglePlay,
                          ),
                          _MiniIconButton(
                            icon: Icons.skip_next_rounded,
                            onTap: player.next,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: loading
            ? Center(
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            : Icon(icon, size: 24, color: AppColors.text),
      ),
    );
  }
}

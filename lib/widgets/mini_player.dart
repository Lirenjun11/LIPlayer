import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/full_player_screen.dart';
import '../state/player_state.dart';
import '../theme.dart';
import 'cover_image.dart';

/// Floating bottom bar showing the current track, like mainstream players.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FullPlayerScreen()),
        ),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: player.progress / 100,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
                child: Row(
                  children: [
                    CoverImage(
                        url: song.artwork, width: 44, height: 44, radius: 12),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.artist.isEmpty ? '未知歌手' : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
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
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 42,
        height: 42,
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            : Icon(icon, size: 26, color: AppColors.text),
      ),
    );
  }
}

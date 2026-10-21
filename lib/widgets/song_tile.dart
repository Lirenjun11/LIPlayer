import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/player_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'cover_image.dart';
import 'song_actions.dart';

/// A single row in a song list.
class SongTile extends StatelessWidget {
  final Song song;
  final bool playing;
  final bool showDuration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Renders the trailing "⋯" button that opens the action sheet.
  final bool showActions;
  final Widget? trailing;

  /// Optional extra entry in the action sheet (e.g. "从歌单移除").
  final String? removeLabel;
  final VoidCallback? onRemove;

  const SongTile({
    super.key,
    required this.song,
    this.playing = false,
    this.showDuration = true,
    this.onTap,
    this.onLongPress,
    this.showActions = true,
    this.trailing,
    this.removeLabel,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: playing ? AppColors.bgCard : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: playing
              ? Border.all(color: AppColors.accent.withValues(alpha: 0.25))
              : null,
        ),
        child: Row(
          children: [
            CoverImage(url: song.artwork, width: 46, height: 46, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title.isEmpty ? '未知歌曲' : song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: playing ? AppColors.accent : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.album.isEmpty
                        ? song.artist
                        : '${song.artist} · ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            if (showDuration)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Builder(
                  builder: (context) {
                    // Prefer the engine-reported length; fall back to metadata
                    // until the track has been played at least once.
                    final total = context.select<PlayerState, Duration>(
                      (p) => p.durationOf(song),
                    );
                    return Text(
                      formatDuration(total),
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    );
                  },
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
            if (showActions)
              IconButton(
                tooltip: '更多',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert,
                    size: 18, color: AppColors.text3),
                onPressed: () => showSongActions(
                  context,
                  song,
                  removeLabel: removeLabel,
                  onRemove: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

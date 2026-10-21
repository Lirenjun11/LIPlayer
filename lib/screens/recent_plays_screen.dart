import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

/// List of the most recently played tracks (newest first, max 100).
class RecentPlaysScreen extends StatelessWidget {
  const RecentPlaysScreen({super.key});

  void _playAll(BuildContext context, PlayerState player) {
    if (player.recentPlays.isEmpty) return;
    player.appendAllAndPlay(player.recentPlays);
    AppToast.show(context, '已加入队列并开始播放（${player.recentPlays.length} 首）');
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the palette (light/dark) changes.
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final songs = player.recentPlays;
    final currentKey = player.currentSong?.uniqueKey;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Lets the frosted mini player blur the list behind it.
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '最近播放',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (songs.isNotEmpty)
            TextButton(
              onPressed: () {
                player.clearRecent();
                AppToast.show(context, '已清空最近播放');
              },
              child: Text(
                '清空',
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
            ),
        ],
      ),
      body: songs.isEmpty
          ? const _EmptyRecent()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        '共 ${songs.length} 首 · 最多保留 ${PlayerState.recentLimit} 首',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _playAll(context, player),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label:
                            const Text('播放全部', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 96),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongTile(
                        song: song,
                        playing: song.uniqueKey == currentKey,
                        onTap: () => player.playNextAndPlay(song),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 44, color: AppColors.text3),
          SizedBox(height: 12),
          Text(
            '还没有播放记录',
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          SizedBox(height: 4),
          Text(
            '播放过的歌曲会自动出现在这里',
            style: TextStyle(fontSize: 11, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

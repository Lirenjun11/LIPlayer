import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

/// Tracks the user marked as favourite.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final library = context.watch<LibraryState>();
    final songs = library.favorites;
    final currentKey = player.currentSong?.uniqueKey;

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '收藏',
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
              onPressed: () async {
                await library.clearFavorites();
                if (!context.mounted) return;
                AppToast.show(context, '已清空收藏');
              },
              child: Text('清空',
                  style: TextStyle(fontSize: 13, color: AppColors.text2)),
            ),
        ],
      ),
      body: songs.isEmpty
          ? const _EmptyFavorites()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        '共 ${songs.length} 首',
                        style: TextStyle(fontSize: 11, color: AppColors.text2),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          player.appendAllAndPlay(songs);
                          AppToast.show(
                              context, '已加入队列并开始播放（${songs.length} 首）');
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('播放全部',
                            style: TextStyle(fontSize: 13)),
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
                        removeLabel: '取消收藏',
                        onRemove: () => library.removeFavorite(song),
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

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border, size: 44, color: AppColors.text3),
          const SizedBox(height: 12),
          Text('还没有收藏的歌曲',
              style: TextStyle(fontSize: 13, color: AppColors.text2)),
          const SizedBox(height: 4),
          Text('长按歌曲选择「收藏」即可加入这里',
              style: TextStyle(fontSize: 11, color: AppColors.text3)),
        ],
      ),
    );
  }
}

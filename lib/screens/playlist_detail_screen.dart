import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';

/// Songs inside a user-created playlist.
class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettings>();
    final player = context.watch<PlayerState>();
    final library = context.watch<LibraryState>();
    final playlist = library.playlists
        .where((p) => p.id == playlistId)
        .cast<SongPlaylist?>()
        .firstWhere((p) => p != null, orElse: () => null);

    if (playlist == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.bg),
        body: Center(
          child: Text('歌单不存在',
              style: TextStyle(fontSize: 13, color: AppColors.text2)),
        ),
      );
    }

    final songs = playlist.songs;
    final currentKey = player.currentSong?.uniqueKey;

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          playlist.name,
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
          IconButton(
            tooltip: '重命名',
            icon: Icon(Icons.sync_alt_rounded,
                size: 19, color: AppColors.text2),
            onPressed: () async {
              final name =
                  await promptPlaylistName(context, initial: playlist.name);
              if (name == null || name.trim().isEmpty) return;
              await library.renamePlaylist(playlist.id, name);
            },
          ),
          IconButton(
            tooltip: '删除歌单',
            icon: Icon(Icons.delete_outline, size: 19, color: AppColors.text2),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('删除歌单'),
                  content: Text('确定删除「${playlist.name}」？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('取消',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.text2)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text('删除',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFFFF7A93))),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              await library.deletePlaylist(playlist.id);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_rounded,
                      size: 44, color: AppColors.text3),
                  const SizedBox(height: 12),
                  Text('歌单还是空的',
                      style: TextStyle(fontSize: 13, color: AppColors.text2)),
                  const SizedBox(height: 4),
                  Text('长按任意歌曲选择「添加到歌单」',
                      style: TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
                  child: Row(
                    children: [
                      Text('共 ${songs.length} 首',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text2)),
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
                        removeLabel: '从歌单移除',
                        onRemove: () =>
                            library.removeFromPlaylist(playlist.id, song),
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

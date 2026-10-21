import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../theme.dart';
import 'app_toast.dart';

/// Bottom sheet with the common actions for a track: favourite, add to a
/// playlist, play next, append to the queue.
Future<void> showSongActions(
  BuildContext context,
  Song song, {
  String? removeLabel,
  VoidCallback? onRemove,
}) async {
  final library = context.read<LibraryState>();
  final player = context.read<PlayerState>();
  final isFavourite = library.isFavorite(song);

  await showModalBottomSheet<void>(
    context: context,
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                children: [
                  Text(
                    song.title.isEmpty ? '未知歌曲' : song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (song.artist.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.text2),
                    ),
                  ],
                ],
              ),
            ),
            _action(
              icon: isFavourite ? Icons.favorite : Icons.favorite_border,
              iconColor: const Color(0xFFFF7A93),
              label: isFavourite ? '取消收藏' : '收藏',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await library.toggleFavorite(song);
                if (!context.mounted) return;
                AppToast.show(
                    context, isFavourite ? '已取消收藏' : '已收藏');
              },
            ),
            _action(
              icon: Icons.playlist_add_rounded,
              label: '添加到歌单',
              onTap: () {
                Navigator.of(sheetContext).pop();
                pickPlaylist(context, song);
              },
            ),
            _action(
              icon: Icons.skip_next_rounded,
              label: '下一首播放',
              onTap: () {
                Navigator.of(sheetContext).pop();
                player.playNextAndPlay(song);
              },
            ),
            _action(
              icon: Icons.queue_music_rounded,
              label: '加入播放队列',
              onTap: () {
                Navigator.of(sheetContext).pop();
                final added = player.appendAll([song]);
                AppToast.show(
                    context, added == 0 ? '已在播放队列' : '已添加到队列');
              },
            ),
            if (removeLabel != null && onRemove != null)
              _action(
                icon: Icons.delete_outline,
                iconColor: const Color(0xFFFF7A93),
                label: removeLabel,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onRemove();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Lets the user pick one of their playlists (or create a new one).
Future<void> pickPlaylist(BuildContext context, Song song) async {
  final library = context.read<LibraryState>();

  final selected = await showModalBottomSheet<SongPlaylist>(
    context: context,
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
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '添加到歌单',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(Icons.add, size: 20, color: AppColors.accent),
                    title: Text(
                      '新建歌单',
                      style: TextStyle(fontSize: 14, color: AppColors.accent),
                    ),
                    onTap: () async {
                      final name = await promptPlaylistName(sheetContext);
                      if (name == null || name.trim().isEmpty) return;
                      final created = await library.createPlaylist(name);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop(created);
                      }
                    },
                  ),
                  for (final playlist in library.playlists)
                    ListTile(
                      leading: Icon(Icons.queue_music_rounded,
                          size: 20, color: AppColors.text2),
                      title: Text(
                        playlist.name,
                        style: TextStyle(fontSize: 14, color: AppColors.text),
                      ),
                      subtitle: Text(
                        '${playlist.songs.length} 首',
                        style: TextStyle(fontSize: 11, color: AppColors.text3),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(playlist),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (selected == null) return;
  final added = await library.addToPlaylist(selected.id, song);
  if (!context.mounted) return;
  AppToast.show(context, added ? '已添加到「${selected.name}」' : '该歌曲已在歌单中');
}

/// Simple name dialog used for creating/renaming playlists.
///
/// Deliberately avoids a TextEditingController: the dialog's exit animation
/// keeps the TextField alive for a moment after the future resolves, and
/// disposing the controller immediately crashed with
/// "A TextEditingController was used after being disposed".
Future<String?> promptPlaylistName(BuildContext context,
    {String initial = ''}) async {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      var text = initial;
      return AlertDialog(
        title: Text(initial.isEmpty ? '新建歌单' : '重命名歌单'),
        content: TextField(
          autofocus: true,
          maxLength: 30,
          style: TextStyle(fontSize: 14, color: AppColors.text),
          decoration: const InputDecoration(hintText: '歌单名称'),
          onChanged: (value) => text = value,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(text),
            child: Text('确定',
                style: TextStyle(fontSize: 13, color: AppColors.accent)),
          ),
        ],
      );
    },
  );
}

Widget _action({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  Color? iconColor,
}) {
  return ListTile(
    leading: Icon(icon, size: 20, color: iconColor ?? AppColors.text2),
    title: Text(label, style: TextStyle(fontSize: 14, color: AppColors.text)),
    onTap: onTap,
  );
}

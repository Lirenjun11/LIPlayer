import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cover_image.dart';
import '../widgets/song_actions.dart';

/// Reorder and delete user-created playlists.
class ManagePlaylistsScreen extends StatelessWidget {
  const ManagePlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettings>();
    final library = context.watch<LibraryState>();
    final playlists = library.playlists;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '管理歌单',
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
            tooltip: '新建歌单',
            icon: Icon(Icons.add, size: 20, color: AppColors.text2),
            onPressed: () async {
              final name = await promptPlaylistName(context);
              if (name == null || name.trim().isEmpty) return;
              await library.createPlaylist(name);
            },
          ),
        ],
      ),
      body: playlists.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_rounded,
                      size: 44, color: AppColors.text3),
                  const SizedBox(height: 12),
                  Text('还没有歌单',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.text2)),
                  const SizedBox(height: 4),
                  Text('点击右上角「+」创建',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(
                    children: [
                      Text(
                        '共 ${playlists.length} 个 · 拖动右侧手柄排序',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    buildDefaultDragHandles: false,
                    itemCount: playlists.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      library.reorderPlaylists(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final cover = playlist.songs.isEmpty
                          ? ''
                          : playlist.songs.first.artwork;
                      return Container(
                        key: ValueKey(playlist.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            cover.isEmpty
                                ? Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC8A2FF)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.queue_music_rounded,
                                        size: 20,
                                        color: const Color(0xFFC8A2FF)),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CoverImage(
                                        url: cover, width: 40, height: 40),
                                  ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    playlist.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${playlist.songs.length} 首',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.text2),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '重命名',
                              icon: Icon(Icons.sync_alt_rounded,
                                  size: 18, color: AppColors.text3),
                              onPressed: () async {
                                final name = await promptPlaylistName(
                                    context,
                                    initial: playlist.name);
                                if (name == null || name.trim().isEmpty) return;
                                await library.renamePlaylist(
                                    playlist.id, name);
                              },
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: const Color(0xFFFF7A93)),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('删除歌单'),
                                    content:
                                        Text('确定删除「${playlist.name}」？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(
                                                dialogContext)
                                            .pop(false),
                                        child: Text('取消',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.text2)),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(true),
                                        child: Text('删除',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFFFF7A93))),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                await library.deletePlaylist(playlist.id);
                                if (!context.mounted) return;
                                AppToast.show(context, '已删除歌单');
                              },
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    3,
                                    (_) => Container(
                                      width: 14,
                                      height: 1.6,
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 1.4),
                                      color: AppColors.text3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

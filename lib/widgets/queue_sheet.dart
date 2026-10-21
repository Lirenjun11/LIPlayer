import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_state.dart';
import '../theme.dart';
import 'song_tile.dart';

/// Bottom sheet listing the current play queue.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final player = context.watch<PlayerState>();
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.text3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('播放队列',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                  Row(
                    children: [
                      Text('${player.playlist.length} 首',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text2)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: player.clearPlaylist,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text('清空',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFFFF8BAB))),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: player.playlist.isEmpty
                  ? Center(
                      child: Text('播放队列为空',
                          style: TextStyle(color: AppColors.text2)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: player.playlist.length,
                      itemBuilder: (context, index) {
                        final song = player.playlist[index];
                        final active = index == player.currentIndex;
                        return SongTile(
                          song: song,
                          playing: active,
                          showDuration: false,
                          onTap: () {
                            player.playAt(index);
                            Navigator.of(context).pop();
                          },
                          removeLabel: '从播放队列移除',
                          onRemove: () => player.removeFromPlaylist(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

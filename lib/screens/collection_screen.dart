import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/player_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cover_image.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

/// Detail page for a toplist / playlist: browse its songs and either play a
/// single track (inserted after the current one) or queue the whole list.
class CollectionScreen extends StatelessWidget {
  final String title;
  final String artwork;
  final String platform;
  final String label;
  final List<Song> songs;

  const CollectionScreen({
    super.key,
    required this.title,
    required this.songs,
    this.artwork = '',
    this.platform = '',
    this.label = '歌单',
  });

  void _playAll(BuildContext context) {
    final player = context.read<PlayerState>();
    player.appendAllAndPlay(songs);
    AppToast.show(context, '已加入队列并开始播放（${songs.length} 首）');
  }

  void _addAll(BuildContext context) {
    final added = context.read<PlayerState>().appendAll(songs);
    AppToast.show(context, added == 0 ? '歌曲已在队列中' : '已添加 $added 首到队列');
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final currentKey = player.currentSong?.uniqueKey;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Lets the frosted mini player blur the list behind it.
      extendBody: true,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 250,
            backgroundColor: AppColors.bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.only(left: 54, right: 16, bottom: 14),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(url: artwork),
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: kCoverFade),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label · ${songs.length} 首',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            if (platform.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '来自 $platform',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.text2),
                              ),
                            ],
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _addAll(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text2,
                          side: const BorderSide(color: AppColors.border),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('加入队列',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _playAll(context),
                        child: Container(
                          height: 36,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: kAccentGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4DFF4D6D),
                                blurRadius: 14,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 18, color: Colors.white),
                              SizedBox(width: 3),
                              Text(
                                '播放全部',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final active = song.uniqueKey == currentKey;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SongTile(
                  song: song,
                  playing: active,
                  onTap: () => player.playNextAndPlay(song),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add_rounded,
                        size: 20, color: AppColors.text2),
                    onPressed: () {
                      final added = player.appendAll([song]);
                      AppToast.show(
                          context, added == 0 ? '已在播放队列' : '已添加到队列末尾');
                    },
                  ),
                ),
              );
            },
          ),
          // Room for the floating player capsule.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

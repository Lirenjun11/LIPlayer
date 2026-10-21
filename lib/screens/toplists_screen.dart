import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_collection.dart';
import '../services/api_service.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cover_image.dart';
import '../widgets/mini_player.dart';
import 'collection_screen.dart';

/// One category of toplists (e.g. "飙升榜").
class _ToplistSection {
  _ToplistSection({required this.title, this.items = const []});

  final String title;
  final List<MusicCollection> items;
}

/// All toplists of the current music source, grouped by category.
class ToplistsScreen extends StatefulWidget {
  final ApiService api;
  final String platform;

  const ToplistsScreen({
    super.key,
    required this.api,
    required this.platform,
  });

  @override
  State<ToplistsScreen> createState() => _ToplistsScreenState();
}

class _ToplistsScreenState extends State<ToplistsScreen> {
  List<_ToplistSection> _groups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final titles = await widget.api.fetchToplistGroups(widget.platform);
      final groups = await Future.wait(titles.map((title) async {
        try {
          final items =
              await widget.api.fetchToplistGroup(widget.platform, title);
          return _ToplistSection(title: title, items: items);
        } catch (_) {
          return _ToplistSection(title: title);
        }
      }));
      if (!mounted) return;
      setState(() {
        _groups = groups.where((g) => g.items.isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _open(MusicCollection item) async {
    AppToast.show(context, '加载榜单...');
    try {
      final platform = item.platform.isEmpty ? widget.platform : item.platform;
      final songs = await widget.api.fetchCollectionDetail(
        'api/external/toplist-detail',
        platform,
        item.id,
        src: item.src,
      );
      if (!mounted) return;
      if (songs.isEmpty) {
        AppToast.show(context, '榜单暂无歌曲');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionScreen(
            title: item.title.isEmpty ? '榜单' : item.title,
            artwork: item.artwork,
            platform: platform,
            label: '榜单',
            songs: songs,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '榜单加载失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '排行榜',
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
            tooltip: '刷新',
            icon: Icon(Icons.sync_rounded, size: 20, color: AppColors.text2),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent),
            ),
            const SizedBox(height: 12),
            Text('正在加载排行榜…',
                style: TextStyle(fontSize: 12, color: AppColors.text2)),
          ],
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 44, color: AppColors.text3),
            const SizedBox(height: 12),
            Text(_error ?? '暂无排行榜',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        for (final group in _groups) ...[
          SliverToBoxAdapter(child: _sectionHeader(group)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ToplistTile(
                  item: group.items[index],
                  onTap: _open,
                ),
                childCount: group.items.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _sectionHeader(_ToplistSection group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: kAccentGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            group.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${group.items.length} 个',
            style: TextStyle(fontSize: 11, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

class _ToplistTile extends StatelessWidget {
  final MusicCollection item;
  final ValueChanged<MusicCollection> onTap;

  const _ToplistTile({required this.item, required this.onTap});

  String _formatCount(int value) {
    if (value <= 0) return '';
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)}亿';
    }
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final count = _formatCount(item.playCount);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CoverImage(url: item.artwork, radius: 12),
                ),
                if (count.isNotEmpty)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title.isEmpty ? '未命名榜单' : item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

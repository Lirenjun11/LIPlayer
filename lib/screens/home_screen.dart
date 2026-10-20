import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_collection.dart';
import '../models/music_platform.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../state/player_state.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/app_toast.dart';
import '../widgets/cover_image.dart';
import '../widgets/platform_picker.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/song_tile.dart';
import 'collection_screen.dart';
import 'daily_recommend_screen.dart';
import 'full_player_screen.dart';
import 'recent_plays_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _bannerController = PageController(viewportFraction: 0.9);
  final _discoverController = ScrollController();
  final _searchListController = ScrollController();
  Timer? _searchDebounce;
  Timer? _bannerTimer;

  static const String _platformKey = 'music_player_platform';

  int _tab = 0;
  int _mineSection = 0;
  int _recommendLimit = DailyRecommendScreen.defaultLimit;
  int _bannerIndex = 0;
  bool _searchOpen = false;

  List<MusicPlatform> _platforms = [];
  String _currentPlatform = '';

  List<ToplistGroup> _toplistGroups = [];
  bool _loadingToplists = false;

  List<MusicCollection> _sheets = [];
  bool _loadingSheets = false;
  bool _sheetsEnd = false;
  int _sheetsPage = 1;

  List<Song> _searchResults = [];
  bool _searching = false;
  bool _searchEnd = false;
  int _searchPage = 1;

  bool _discoveryStarted = false;

  late final PlayerState _player;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerState>();
    _player.onError = (msg) {
      if (!mounted) return;
      AppToast.show(context, msg);
    };
    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final items = _bannerItems;
      if (!mounted || !_bannerController.hasClients || items.length < 2) return;
      _bannerController.animateToPage(
        (_bannerIndex + 1) % items.length,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
    _discoverController.addListener(_onDiscoverScroll);
    _searchListController.addListener(_onSearchScroll);
    _refreshRecommendLimit();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDiscovery());
  }

  Future<void> _refreshRecommendLimit() async {
    final value = await DailyRecommendScreen.loadLimit();
    if (!mounted || value == _recommendLimit) return;
    setState(() => _recommendLimit = value);
  }

  /// Infinite scroll for search results.
  void _onSearchScroll() {
    if (!_searchListController.hasClients) return;
    final position = _searchListController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMoreSearch();
    }
  }

  void _loadMoreSearch() {
    if (_searching || _searchEnd || _searchResults.isEmpty) return;
    _search(more: true);
  }

  void _ensureSearchScrollable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchListController.hasClients) return;
      if (_searchListController.position.maxScrollExtent <= 0) {
        _loadMoreSearch();
      }
    });
  }

  /// Infinite scroll: fetch the next page shortly before reaching the bottom.
  void _onDiscoverScroll() {
    if (!_discoverController.hasClients) return;
    final position = _discoverController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreSheets();
    }
  }

  void _loadMoreSheets() {
    if (_loadingSheets || _sheetsEnd || _sheets.isEmpty) return;
    _loadSheets(more: true);
  }

  /// The first page may not fill the viewport, in which case no scroll happens
  /// and the next page would never load.
  void _ensureScrollable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_discoverController.hasClients) return;
      if (_discoverController.position.maxScrollExtent <= 0) {
        _loadMoreSheets();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _bannerTimer?.cancel();
    _discoverController
      ..removeListener(_onDiscoverScroll)
      ..dispose();
    _searchListController
      ..removeListener(_onSearchScroll)
      ..dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _bannerController.dispose();
    _player.onError = null;
    super.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  // ---- Data ----------------------------------------------------------------

  Future<void> _initDiscovery() async {
    if (_discoveryStarted) return;
    _discoveryStarted = true;
    try {
      final platforms = await _api.fetchPlatforms();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_platformKey) ?? '';
      setState(() {
        _platforms = platforms;
        // Restore the platform picked last time when it is still available.
        if (platforms.any((p) => p.platform == saved)) {
          _currentPlatform = saved;
        } else {
          _currentPlatform =
              platforms.isNotEmpty ? platforms.first.platform : '';
        }
      });
      if (_currentPlatform.isNotEmpty) {
        await prefs.setString(_platformKey, _currentPlatform);
      }
      await _loadDiscovery();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _loadDiscovery() async {
    if (_currentPlatform.isEmpty) return;
    await Future.wait([_loadToplists(), _loadSheets()]);
  }

  Future<void> _loadToplists() async {
    if (_currentPlatform.isEmpty) return;
    setState(() {
      _loadingToplists = true;
      _toplistGroups = [];
    });
    try {
      final titles = await _api.fetchToplistGroups(_currentPlatform);
      final groups = await Future.wait(titles.map((title) async {
        try {
          final items = await _api.fetchToplistGroup(_currentPlatform, title);
          return ToplistGroup(title: title, items: items);
        } catch (_) {
          return ToplistGroup(title: title);
        }
      }));
      if (!mounted) return;
      setState(() {
        _toplistGroups = groups;
        _bannerIndex = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _toplistGroups = []);
    } finally {
      if (mounted) setState(() => _loadingToplists = false);
    }
  }

  Future<void> _loadSheets({bool more = false}) async {
    if (_currentPlatform.isEmpty) return;
    final page = more ? _sheetsPage + 1 : 1;
    setState(() {
      _loadingSheets = true;
      if (!more) _sheets = [];
    });
    try {
      final result = await _api.fetchSheets(_currentPlatform, page);
      if (!mounted) return;
      // Drop duplicates so repeated pages cannot grow the list forever.
      final known = _sheets.map((s) => '${s.platform}_${s.id}').toSet();
      final fresh = result.items
          .where((s) => known.add('${s.platform}_${s.id}'))
          .toList();
      setState(() {
        _sheetsPage = page;
        // An empty page means there is nothing left to fetch; stop the loop.
        _sheetsEnd = result.isEnd || (more && fresh.isEmpty);
        _sheets = more ? [..._sheets, ...fresh] : result.items;
      });
      _ensureScrollable();
    } catch (_) {
      if (!mounted) return;
      if (!more) setState(() => _sheets = []);
    } finally {
      if (mounted) setState(() => _loadingSheets = false);
    }
  }

  Future<void> _search({bool more = false}) async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      _toast('请输入关键词');
      return;
    }
    if (_currentPlatform.isEmpty) return;
    final page = more ? _searchPage + 1 : 1;
    setState(() {
      _searching = true;
      if (!more) {
        _searchResults = [];
        _searchEnd = false;
      }
    });
    try {
      final result = await _api.search(_currentPlatform, keyword, page);
      if (!mounted) return;
      final known = _searchResults.map((s) => s.uniqueKey).toSet();
      final fresh =
          result.items.where((s) => known.add(s.uniqueKey)).toList();
      setState(() {
        _searchPage = page;
        _searchEnd = result.isEnd || (more && fresh.isEmpty);
        _searchResults = more ? [..._searchResults, ...fresh] : result.items;
      });
      _ensureSearchScrollable();
    } catch (e) {
      _toast('搜索失败: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onKeywordChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_searchController.text.trim().isNotEmpty) _search();
    });
  }

  Future<void> _openCollection(
      MusicCollection item, String endpoint, String label) async {
    _toast('加载$label...');
    try {
      final platform = item.platform.isEmpty ? _currentPlatform : item.platform;
      final songs = await _api.fetchCollectionDetail(
        endpoint,
        platform,
        item.id,
        src: item.src,
      );
      if (!mounted) return;
      if (songs.isEmpty) {
        _toast('$label暂无歌曲');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionScreen(
            title: item.title.isEmpty ? label : item.title,
            artwork: item.artwork,
            platform: platform,
            label: label,
            songs: songs,
          ),
        ),
      );
    } catch (e) {
      _toast('$label加载失败');
    }
  }

  /// Plays a single track right after the current one, keeping the queue.
  void _playFromSearch(Song song) {
    context.read<PlayerState>().playNextAndPlay(song);
  }

  void _playAllSearch() {
    if (_searchResults.isEmpty) return;
    context.read<PlayerState>().appendAllAndPlay(_searchResults);
    _toast('已加入队列并开始播放（${_searchResults.length} 首）');
  }

  void _toast(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  void _selectPlatform(MusicPlatform platform) {
    if (platform.platform == _currentPlatform) return;
    setState(() {
      _currentPlatform = platform.platform;
      _searchResults = [];
      _searchEnd = false;
      _bannerIndex = 0;
    });
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_platformKey, platform.platform));
    _loadDiscovery();
  }

  void _openSearch() {
    setState(() {
      _tab = 0;
      _searchOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() => _searchOpen = false);
  }

  void _openPlayer() {
    final player = context.read<PlayerState>();
    if (player.currentSong == null) {
      _toast('还没有播放中的歌曲');
      return;
    }
    Navigator.of(context).push(fullPlayerRoute());
  }

  // ---- Derived data --------------------------------------------------------

  List<MusicCollection> get _bannerItems {
    final items = <MusicCollection>[];
    for (final group in _toplistGroups) {
      for (final item in group.items) {
        if (items.length >= 5) return items;
        items.add(item);
      }
    }
    return items;
  }

  // ---- Shell ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Rebuild when the palette (light/dark) changes.
    context.watch<AppSettings>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: _body(),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _body() {
    if (_searchOpen) return _searchTab();
    return _tab == 2 ? _mineTab() : _discoverTab();
  }

  Widget _bottomNav() {
    const barHeight = 56.0;
    const buttonSize = 64.0;
    const bottomMargin = 8.0;
    // Keeps the button's bottom on the same baseline as the tab labels, so the
    // disc rises 16px above the pill instead of floating in its centre.
    const bottomGap = 8.0;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    // Only the centre entry needs playback state; watching it here rebuilt the
    // entire home page on every position tick (~5 times per second).
    final stackHeight = buttonSize + bottomGap + bottomMargin + bottomInset;
    final pillBottom = bottomMargin + bottomInset;
    final pillTop = stackHeight - pillBottom - barHeight;
    // Centre of the disc, expressed inside the pill's own coordinates.
    final notchCenterY = (buttonSize / 2) - pillTop;

    return SizedBox(
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 14,
            right: 14,
            bottom: pillBottom,
            height: barHeight,
            child: CustomPaint(
              painter: _PillPainter(
                color: AppColors.isDark
                    ? const Color(0xFF10131A)
                    : AppColors.bgCard,
                borderColor: AppColors.border,
                dropShadowColor: AppColors.isDark
                    ? const Color(0xCC000000)
                    : const Color(0x1A000000),
                notchShadowColor: AppColors.isDark
                    ? const Color(0x99000000)
                    : const Color(0x14000000),
                notchCenterY: notchCenterY,
                notchRadius: buttonSize / 2 + 3,
              ),
              child: Row(
                children: [
                  _navItem(0, Icons.explore_outlined, Icons.explore, '发现'),
                  const SizedBox(width: 76),
                  _navItem(2, Icons.person_outline, Icons.person, '我的'),
                ],
              ),
            ),
          ),
          // The disc sits in the hole cut out of the pill.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Consumer<PlayerState>(
                builder: (context, player, _) => _playerEntry(player),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    // The search page is reachable from 发现, so keep that tab highlighted.
    final selected = _tab == index;
    return Expanded(
      // No InkWell: desktop hover/highlight rectangles look out of place here.
      // Selection is conveyed purely by icon + label colour.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _tab = index;
          _searchOpen = false;
        }),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 23,
              color: selected ? AppColors.accent : AppColors.text3,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.accent : AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Centre entry that opens the full player; shows the current artwork.
  Widget _playerEntry(PlayerState player) {
    final song = player.currentSong;
    final playing = song != null;
    final hasArt = song != null && song.artwork.isNotEmpty;

    Widget inner;
    if (hasArt) {
      inner = CoverImage(url: song.artwork, width: 58, height: 58);
    } else if (playing) {
      inner = Container(
        decoration: BoxDecoration(gradient: kAccentGradient),
        alignment: Alignment.center,
        child: const Icon(Icons.graphic_eq, size: 22, color: Colors.white),
      );
    } else {
      inner = Container(
        color: AppColors.bgCard2,
        alignment: Alignment.center,
        child: Icon(Icons.play_arrow_rounded,
            size: 24, color: AppColors.text2),
      );
    }

    return GestureDetector(
      onTap: _openPlayer,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.isDark
                ? const Color(0x26FFFFFF)
                : const Color(0x14000000),
          ),
          boxShadow: [
            BoxShadow(
              // A heavy black halo looks wrong on the light palette.
              color: AppColors.isDark
                  ? const Color(0x99000000)
                  : const Color(0x1A000000),
              blurRadius: AppColors.isDark ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(child: inner),
      ),
    );
  }

  // ---- Discover ------------------------------------------------------------

  Widget _discoverTab() {
    final banners = _bannerItems;
    return CustomScrollView(
      controller: _discoverController,
      slivers: [
        SliverToBoxAdapter(child: _discoverHeader()),
        SliverToBoxAdapter(child: _searchEntry()),
        if (banners.isNotEmpty)
          SliverToBoxAdapter(child: _bannerSection(banners)),
        SliverToBoxAdapter(
          child: _sectionHeader('排行榜', trailing: '实时更新'),
        ),
        if (_loadingToplists && _toplistGroups.isEmpty)
          SliverToBoxAdapter(child: _loadingTip('排行榜加载中...'))
        else if (_toplistGroups.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const _Tip('当前平台暂无排行榜'),
            ),
          )
        else
          for (final group in _toplistGroups.take(3))
            SliverToBoxAdapter(child: _toplistRow(group)),
        SliverToBoxAdapter(
          child: _sectionHeader('推荐歌单', trailing: '大家都在听'),
        ),
        if (_loadingSheets && _sheets.isEmpty)
          SliverToBoxAdapter(child: _loadingTip('歌单加载中...'))
        else if (_sheets.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const _Tip('当前平台暂无推荐歌单'),
            ),
          )
        else
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
                (context, index) {
                  final sheet = _sheets[index];
                  return _SheetTile(
                    sheet: sheet,
                    onTap: () => _openCollection(
                        sheet, 'api/external/sheet-detail', '歌单'),
                  );
                },
                childCount: _sheets.length,
              ),
            ),
          ),
        if (_sheets.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
              child: Center(
                child: _loadingSheets
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: AppColors.accent,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '正在加载更多',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.text2),
                          ),
                        ],
                      )
                    : Text(
                        _sheetsEnd ? '已经到底啦' : '上滑加载更多',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.text3),
                      ),
              ),
            ),
          ),
        // Extra room so content does not crowd the floating player button.
        const SliverToBoxAdapter(child: SizedBox(height: 44)),
      ],
    );
  }

  Widget _discoverHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '今天想听点什么？',
                  style: TextStyle(fontSize: 12, color: AppColors.text2),
                ),
              ],
            ),
          ),
          _platformChip(),
        ],
      ),
    );
  }

  Widget _platformChip() {
    return GestureDetector(
      onTap: _platforms.isEmpty
          ? null
          : () => showPlatformPicker(
                context,
                platforms: _platforms,
                current: _currentPlatform,
                onSelect: _selectPlatform,
              ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, size: 14, color: AppColors.accent),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                _currentPlatform.isEmpty ? '音乐源' : _currentPlatform,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: AppColors.text2),
          ],
        ),
      ),
    );
  }

  Widget _searchEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: GestureDetector(
        onTap: _openSearch,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: AppColors.text3),
              SizedBox(width: 8),
              Text(
                '搜索歌曲、歌手、专辑',
                style: TextStyle(fontSize: 13, color: AppColors.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerSection(List<MusicCollection> items) {
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _bannerIndex = index),
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _BannerCard(
                  item: item,
                  onTap: () => _openCollection(
                      item, 'api/external/toplist-detail', '排行榜'),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: i == _bannerIndex ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color:
                      i == _bannerIndex ? AppColors.accent : AppColors.text3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionHeader(String title, {String? trailing, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: kAccentGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            GestureDetector(
              onTap: onTap,
              child: Text(
                trailing,
                style: TextStyle(fontSize: 11, color: AppColors.text2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toplistRow(ToplistGroup group) {
    if (group.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          child: Text(
            group.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ),
        SizedBox(
          height: 154,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: group.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = group.items[index];
              return _ToplistTile(
                item: item,
                onTap: () => _openCollection(
                    item, 'api/external/toplist-detail', '排行榜'),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _loadingTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text,
            style: TextStyle(fontSize: 13, color: AppColors.text2)),
      ),
    );
  }

  // ---- Search --------------------------------------------------------------

  Widget _searchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 16, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回发现',
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.text),
                onPressed: _closeSearch,
              ),
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search,
                          size: 18, color: AppColors.text3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            setState(() {});
                            _onKeywordChanged(value);
                          },
                          onSubmitted: (_) => _search(),
                          style: TextStyle(
                              fontSize: 14, color: AppColors.text),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '搜索歌曲、歌手、专辑',
                            hintStyle: TextStyle(
                                color: AppColors.text3, fontSize: 13),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close,
                              size: 17, color: AppColors.text3),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                              _searchEnd = false;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _search(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _searchBody()),
      ],
    );
  }

  Widget _searchBody() {
    if (_searchResults.isEmpty && !_searching) {
      return const _EmptyState(icon: '♪', text: '输入关键词，发现喜欢的声音');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
          child: Row(
            children: [
              Text(
                _searching ? '搜索中...' : '共 ${_searchResults.length} 首',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _searchResults.isEmpty ? null : _playAllSearch,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('播放全部', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _searchListController,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            itemCount: _searchResults.length + (_searchEnd ? 0 : 1),
            itemBuilder: (context, index) {
              if (index >= _searchResults.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _searching
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: AppColors.accent,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('正在加载更多',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.text2)),
                            ],
                          )
                        : Text(
                            '上滑加载更多',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.text3),
                          ),
                  ),
                );
              }
              final song = _searchResults[index];
              return SongTile(
                song: song,
                onTap: () => _playFromSearch(song),
                trailing: IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      size: 22, color: AppColors.accent),
                  onPressed: () {
                    final player = context.read<PlayerState>();
                    player.addToPlaylist(song);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- Mine ----------------------------------------------------------------

  Widget _mineTab() {
    final player = context.watch<PlayerState>();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _mineHeader()),
        SliverToBoxAdapter(child: _profileCard(player)),
        SliverToBoxAdapter(child: _promoBanner()),
        SliverToBoxAdapter(child: _mineTabs()),
        ..._mineSectionSlivers(player),
        const SliverToBoxAdapter(child: SizedBox(height: 44)),
      ],
    );
  }

  Widget _mineHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 6, 4),
      child: Row(
        children: [
          Text(
            '我的',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.text,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '同步音源',
            icon: Icon(Icons.sync_rounded,
                size: 20, color: AppColors.text2),
            onPressed: _importSources,
          ),
          IconButton(
            tooltip: '搜索',
            icon: Icon(Icons.search, size: 21, color: AppColors.text2),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: '设置',
            icon: Icon(Icons.settings_outlined,
                size: 21, color: AppColors.text2),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _profileCard(PlayerState player) {
    final song = player.currentSong;
    final hasArt = song != null && song.artwork.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 122,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasArt)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: CoverImage(url: song.artwork),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A2440), Color(0xFF1A2433)],
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xD90A0B10), Color(0x730A0B10)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: kAccentGradient,
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: const Icon(Icons.music_note,
                        size: 26, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '音乐爱好者',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFD37A), Color(0xFFE8A33D)],
                                ),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Text(
                                'VIP',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3A2400),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => setState(() => _tab = 0),
                          child: Row(
                            children: [
                              Text(
                                _currentPlatform.isEmpty
                                    ? '去发现今日推荐'
                                    : '$_currentPlatform · 去发现今日推荐',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 14, color: Color(0xCCFFFFFF)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '同步音源',
                    icon: const Icon(Icons.sync_rounded,
                        size: 20, color: Colors.white),
                    onPressed: _importSources,
                  ),
                  IconButton(
                    tooltip: '播放队列',
                    icon: const Icon(Icons.mail_outline,
                        size: 20, color: Colors.white),
                    onPressed: () => showQueueSheet(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: GestureDetector(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DailyRecommendScreen(
                api: _api,
                platform: _currentPlatform,
                recentPlays: context.read<PlayerState>().recentPlays,
              ),
            ),
          );
          _refreshRecommendLimit();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.card_giftcard,
                    size: 15, color: AppColors.accent),
              ),
              const SizedBox(width: 8),
              Text(
                '每日推荐',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D2A00),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF8A6B1F)),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFFD37A),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '每天 $_recommendLimit 首 · 按口味生成',
                style: TextStyle(fontSize: 11, color: AppColors.text2),
              ),
              Icon(Icons.chevron_right, size: 16, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mineTabs() {
    const tabs = ['音乐', '队列', '音乐源'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _mineSection = i),
              child: Padding(
                padding: const EdgeInsets.only(right: 26),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          tabs[i],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: _mineSection == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: _mineSection == i
                                ? AppColors.text
                                : AppColors.text2,
                          ),
                        ),
                        if (i == 2 && _platforms.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.accent2.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_platforms.length}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC9A2FF),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 18,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _mineSection == i
                            ? AppColors.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _mineSectionSlivers(PlayerState player) {
    switch (_mineSection) {
      case 1:
        return _queueSection(player);
      case 2:
        return _sourceSection();
      default:
        return _musicSection(player);
    }
  }

  List<Widget> _musicSection(PlayerState player) {
    final toplistCount = _toplistGroups
        .fold<int>(0, (sum, group) => sum + group.items.length);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _StatCard(
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFFF7A93),
                      label: '收藏',
                      count: player.playlist.length,
                      onTap: () => showQueueSheet(context),
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.phone_iphone_rounded,
                      color: const Color(0xFF7A8CFF),
                      label: '音乐源',
                      count: _platforms.length,
                      onTap: () => setState(() => _mineSection = 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _StatCard(
                      icon: Icons.library_music_rounded,
                      color: const Color(0xFF7BD8C0),
                      label: '歌单',
                      count: _sheets.length,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.bar_chart_rounded,
                      color: const Color(0xFFC8A2FF),
                      label: '榜单',
                      count: toplistCount,
                      onTap: () => setState(() => _tab = 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _sectionHeader(
          '我的音乐',
          trailing: player.playlist.isEmpty ? null : '${player.playlist.length} 首',
          onTap: player.playlist.isEmpty ? null : () => showQueueSheet(context),
        ),
      ),
      SliverToBoxAdapter(
        child: _MineRow(
          icon: Icons.favorite,
          iconColor: const Color(0xFFFF7A93),
          title: '我喜欢的音乐',
          subtitle: '${player.playlist.length} 首',
          onTap: () => showQueueSheet(context),
        ),
      ),
      SliverToBoxAdapter(
        child: _MineRow(
          icon: Icons.history_rounded,
          iconColor: const Color(0xFF7A8CFF),
          title: '最近播放',
          subtitle: player.recentPlays.isEmpty
              ? '暂无播放记录'
              : '${player.recentPlays.length} 首 · ${player.recentPlays.first.title.isEmpty ? '未知歌曲' : player.recentPlays.first.title}',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RecentPlaysScreen()),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _MineRow(
          icon: Icons.sync_alt_rounded,
          iconColor: const Color(0xFF7BD8C0),
          title: '导入其他 APP 的歌单',
          subtitle: '从音乐源同步',
          onTap: _importSources,
        ),
      ),
      if (player.currentSong != null)
        SliverToBoxAdapter(child: _nowPlayingCard(player)),
    ];
  }

  List<Widget> _queueSection(PlayerState player) {
    return [
      SliverToBoxAdapter(
        child: _sectionHeader(
          '播放队列',
          trailing: player.playlist.isEmpty ? null : '${player.playlist.length} 首',
          onTap: player.playlist.isEmpty
              ? null
              : () => showQueueSheet(context),
        ),
      ),
      if (player.playlist.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: _EmptyState(icon: '♫', text: '队列还是空的，去发现页挑一首吧'),
          ),
        )
      else
        SliverList.builder(
          itemCount: player.playlist.length,
          itemBuilder: (context, index) {
            final song = player.playlist[index];
            final active = index == player.currentIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SongTile(
                song: song,
                playing: active,
                onTap: () => player.playAt(index),
                trailing: IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: AppColors.text3),
                  onPressed: () => player.removeFromPlaylist(index),
                ),
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _sourceSection() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
          child: Row(
            children: [
              Text(
                '音乐源',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_platforms.length} 个已启用',
                style: TextStyle(fontSize: 11, color: AppColors.text2),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _importSources,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('同步音源', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _platformList()),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            '点击「同步音源」从服务端获取最新的音源列表',
            style: TextStyle(fontSize: 11, color: AppColors.text3),
          ),
        ),
      ),
    ];
  }

  Future<void> _importSources() async {
    try {
      final platforms = await _api.fetchPlatforms();
      if (!mounted) return;
      setState(() {
        _platforms = platforms;
        if ((_currentPlatform.isEmpty || platforms
                .every((p) => p.platform != _currentPlatform)) &&
            platforms.isNotEmpty) {
          _currentPlatform = platforms.first.platform;
        }
      });
      _toast('已同步 ${platforms.length} 个音源');
      if (_toplistGroups.isEmpty && _currentPlatform.isNotEmpty) {
        _loadDiscovery();
      }
    } catch (e) {
      _toast('同步失败: $e');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          api: _api,
          platforms: _platforms,
          currentPlatform: _currentPlatform,
          onPlatformChanged: _selectPlatform,
        ),
      ),
    );
    _refreshRecommendLimit();
  }

  Widget _nowPlayingCard(PlayerState player) {
    final song = player.currentSong!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF221726), Color(0xFF161822)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CoverImage(url: song.artwork, width: 52, height: 52, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在播放',
                    style: TextStyle(fontSize: 10, color: AppColors.text2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.title.isEmpty ? '未知歌曲' : song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist.isEmpty ? '未知歌手' : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: player.togglePlay,
              icon: Icon(
                player.isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 38,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformList() {
    if (_platforms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _Tip('未获取到音乐源'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _platforms.length; i++)
              InkWell(
                onTap: () => _selectPlatform(_platforms[i]),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      Icon(
                        _platforms[i].platform == _currentPlatform
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: _platforms[i].platform == _currentPlatform
                            ? AppColors.accent
                            : AppColors.text3,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _platforms[i].platform,
                          style: TextStyle(
                            fontSize: 13,
                            color: _platforms[i].platform == _currentPlatform
                                ? AppColors.text
                                : AppColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Cards -----------------------------------------------------------------

class _BannerCard extends StatelessWidget {
  final MusicCollection item;
  final VoidCallback onTap;

  const _BannerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverImage(url: item.artwork),
              const DecoratedBox(decoration: BoxDecoration(gradient: kCoverFade)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.platform.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.platform,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      item.title.isEmpty ? '热门推荐' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.playCount > 0
                          ? '${formatCount(item.playCount)} 次播放'
                          : '点击查看榜单',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xCCFFFFFF)),
                    ),
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

class _ToplistTile extends StatelessWidget {
  final MusicCollection item;
  final VoidCallback onTap;

  const _ToplistTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CoverImage(url: item.artwork, width: 104, height: 104),
            ),
            const SizedBox(height: 7),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.playCount > 0
                  ? '${formatCount(item.playCount)} 次播放'
                  : '实时榜单',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final MusicCollection sheet;
  final VoidCallback onTap;

  const _SheetTile({required this.sheet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CoverImage(url: sheet.artwork),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: kCoverFade),
                  ),
                ),
                if (sheet.playCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x8C000000),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.headphones,
                              size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            formatCount(sheet.playCount),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            sheet.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Statistic tile used on the "我的" page, styled after mainstream players:
/// a pastel icon block with stacked plates plus label and count.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: 12,
                    child: _plate(color.withValues(alpha: 0.18), 44),
                  ),
                  Positioned(
                    right: 7,
                    top: 6,
                    child: _plate(color.withValues(alpha: 0.3), 46),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withValues(alpha: 0.85),
                            color.withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plate(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _MineRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _MineRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
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
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded pill with a circular hole cut out for the player disc, plus an
/// inner shadow around the hole so the disc looks recessed.
class _PillPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final Color dropShadowColor;
  final Color notchShadowColor;
  final double notchCenterY;
  final double notchRadius;

  const _PillPainter({
    required this.color,
    required this.borderColor,
    required this.notchCenterY,
    required this.notchRadius,
    this.dropShadowColor = const Color(0xCC000000),
    this.notchShadowColor = const Color(0x99000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ));
    final hole = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(size.width / 2, notchCenterY),
        radius: notchRadius,
      ));
    final pill = Path.combine(PathOperation.difference, bar, hole);

    // Drop shadow of the whole pill.
    canvas.drawShadow(pill, dropShadowColor, AppColors.isDark ? 12 : 8, false);

    canvas.drawPath(pill, Paint()..color = color);
    canvas.drawPath(
      pill,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Inner shadow hugging the hole => depth.
    canvas.drawCircle(
      Offset(size.width / 2, notchCenterY),
      notchRadius + 1,
      Paint()
        ..color = notchShadowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppColors.isDark ? 7 : 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.dropShadowColor != dropShadowColor ||
      oldDelegate.notchShadowColor != notchShadowColor ||
      oldDelegate.notchCenterY != notchCenterY ||
      oldDelegate.notchRadius != notchRadius;
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.text2)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon,
              style: TextStyle(
                  fontSize: 42, color: AppColors.text3, height: 1.2)),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(fontSize: 13, color: AppColors.text2)),
        ],
      ),
    );
  }
}

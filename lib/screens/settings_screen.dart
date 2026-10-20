import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_version.dart';
import '../models/audio_quality.dart';
import '../services/release_service.dart';
import '../models/music_platform.dart';
import '../services/api_service.dart';
import '../state/app_settings.dart';
import '../state/auth_state.dart';
import '../state/player_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import 'daily_recommend_screen.dart';

/// Standalone settings page (previously a bottom sheet).
class SettingsScreen extends StatefulWidget {
  final ApiService api;
  final List<MusicPlatform> platforms;
  final String currentPlatform;
  final ValueChanged<MusicPlatform> onPlatformChanged;

  const SettingsScreen({
    super.key,
    required this.api,
    required this.platforms,
    required this.currentPlatform,
    required this.onPlatformChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<MusicPlatform> _platforms = List<MusicPlatform>.from(
    widget.platforms,
  );
  late String _platform = widget.currentPlatform;
  int _limit = DailyRecommendScreen.defaultLimit;
  bool _syncing = false;
  bool _downloading = false;
  bool _checkingUpdate = false;
  String? _latestVersion;
  int _ipaBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadLimit();
    _checkLatest();
    _refreshIpaCache();
  }

  Future<void> _refreshIpaCache() async {
    final bytes = await ReleaseService().downloadedBytes();
    if (mounted) setState(() => _ipaBytes = bytes);
  }

  Future<void> _clearIpaCache() async {
    await ReleaseService().clearDownloads();
    await _refreshIpaCache();
    if (!mounted) return;
    AppToast.show(context, '已删除本地安装包');
  }

  Future<void> _loadLimit() async {
    final value = await DailyRecommendScreen.loadLimit();
    if (mounted) setState(() => _limit = value);
  }

  /// Compares the running build with the newest release.
  Future<void> _checkLatest() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final asset = await ReleaseService().fetchLatest();
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      _latestVersion = asset?.version;
    });
  }

  String get _updateLabel {
    if (_checkingUpdate) return '检查中…';
    final latest = _latestVersion;
    if (latest == null || latest.isEmpty) return '未检测到';
    if (latest == kAppVersion) return '已是最新';
    return '新版本 $latest';
  }

  // ---- Actions -------------------------------------------------------------

  /// Downloads the newest release IPA and hands it to another app.
  ///
  /// iOS does not allow an app to install an IPA by itself, so the file is
  /// shared through the system sheet (TrollStore / Files).
  Future<void> _downloadLatest() async {
    setState(() => _downloading = true);
    final service = ReleaseService();
    final asset = await service.fetchLatest();
    if (!mounted) return;
    setState(() => _downloading = false);

    if (asset == null) {
      AppToast.show(context, '获取安装包失败，请检查网络或稍后重试');
      return;
    }

    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text(
            '正在下载安装包',
            style: TextStyle(fontSize: 15, color: AppColors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: value == 0 ? null : value,
                    minHeight: 6,
                    backgroundColor: AppColors.bgCard2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) => Text(
                  '${(value * 100).toStringAsFixed(0)}% · '
                  '${asset.sizeMb.toStringAsFixed(1)} MB',
                  style: TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final file = await service.download(
        asset,
        onProgress: (value) => progress.value = value,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      setState(() => _latestVersion = asset.version);
      _refreshIpaCache();
      _showInstallOptions(file);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      AppToast.show(context, '下载失败：$e');
    }
  }

  void _showInstallOptions(File file) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
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
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '安装包已下载',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: Text(
                  'iOS 不允许 App 直接安装 IPA，请用 TrollStore 或「文件」打开',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ),
              ListTile(
                title: Text('用其他程序打开',
                    style: TextStyle(fontSize: 14, color: AppColors.text)),
                subtitle: Text('选择 TrollStore / 存储到文件',
                    style: TextStyle(fontSize: 11, color: AppColors.text2)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await SharePlus.instance.share(
                    ShareParams(files: [XFile(file.path)]),
                  );
                },
              ),
              ListTile(
                title: Text('关闭',
                    style: TextStyle(fontSize: 14, color: AppColors.text2)),
                onTap: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickTheme() async {
    final settings = context.read<AppSettings>();
    final selected = await _pick<ThemeMode>(
      title: '主题',
      values: ThemeMode.values,
      current: settings.themeMode,
      labelOf: AppSettings.themeLabel,
    );
    if (selected == null) return;
    await settings.setThemeMode(selected);
  }

  Future<void> _pickFont() async {
    final settings = context.read<AppSettings>();
    final selected = await _pick<double>(
      title: '字体大小',
      values: AppSettings.fontOptions,
      current: settings.fontScale,
      labelOf: AppSettings.labelOf,
    );
    if (selected == null) return;
    await settings.setFontScale(selected);
  }

  Future<void> _pickLimit() async {
    final selected = await _pick<int>(
      title: '每日推荐数量',
      values: DailyRecommendScreen.limitOptions,
      current: _limit,
      labelOf: (value) => '$value 首',
    );
    if (selected == null) return;
    await DailyRecommendScreen.saveLimit(selected);
    if (!mounted) return;
    setState(() => _limit = selected);
    AppToast.show(context, '每日推荐已设为 $selected 首');
  }

  Future<void> _pickQuality(PlayerState player) async {
    final selected = await _pick<AudioQuality>(
      title: '播放音质',
      values: AudioQuality.values,
      current: player.quality,
      labelOf: (value) => '${value.label} · ${value.description}',
    );
    if (selected == null) return;
    await player.setQuality(selected);
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final platforms = await widget.api.fetchPlatforms();
      if (!mounted) return;
      setState(() {
        _platforms = platforms;
        if (platforms.isNotEmpty &&
            !platforms.any((p) => p.platform == _platform)) {
          _platform = platforms.first.platform;
          widget.onPlatformChanged(platforms.first);
        }
        _syncing = false;
      });
      AppToast.show(context, '已同步 ${platforms.length} 个音源');
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      AppToast.show(context, '同步失败：$e');
    }
  }

  Future<void> _pickPlatform() async {
    if (_platforms.isEmpty) {
      AppToast.show(context, '暂无音源，请先同步');
      return;
    }
    final selected = await showModalBottomSheet<MusicPlatform>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
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
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '选择音乐源',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _platforms.length,
                  itemBuilder: (context, index) {
                    final platform = _platforms[index];
                    final selected = platform.platform == _platform;
                    return ListTile(
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 19,
                        color:
                            selected ? AppColors.accent : AppColors.text3,
                      ),
                      title: Text(
                        platform.platform,
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                      subtitle: platform.supportedSearchType.isEmpty
                          ? null
                          : Text(
                              platform.supportedSearchType
                                  .map(_typeLabel)
                                  .join(' · '),
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.text3),
                            ),
                      onTap: () => Navigator.of(ctx).pop(platform),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    _selectPlatform(selected);
  }

  void _selectPlatform(MusicPlatform platform) {
    if (platform.platform == _platform) return;
    setState(() => _platform = platform.platform);
    widget.onPlatformChanged(platform);
    AppToast.show(context, '已切换到 ${platform.platform}');
  }

  Future<void> _logout() async {
    final auth = context.read<AuthState>();
    Navigator.of(context).pop();
    auth.logout();
  }

  Future<T?> _pick<T>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T value) labelOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
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
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              for (final value in values)
                ListTile(
                  leading: Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 19,
                    color:
                        value == current ? AppColors.accent : AppColors.text3,
                  ),
                  title: Text(
                    labelOf(value),
                    style: TextStyle(
                      fontSize: 14,
                      color: value == current
                          ? AppColors.accent
                          : AppColors.text,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final settings = context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          '设置',
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          _sectionTitle('外观'),
          _card([
            // Icons are omitted on purpose: adding new glyphs changes the
            // tree-shaken MaterialIcons font, which blocks Shorebird patches.
            _row(
              title: '主题',
              value: AppSettings.themeLabel(settings.themeMode),
              onTap: _pickTheme,
            ),
            _divider(),
            _row(
              title: '字体大小',
              value: settings.fontLabel,
              onTap: _pickFont,
            ),
          ]),
          _sectionTitle('播放'),
          _card([
            _row(
              icon: Icons.auto_awesome_outlined,
              title: '每日推荐数量',
              value: '$_limit 首',
              onTap: _pickLimit,
            ),
            _divider(),
            _row(
              icon: Icons.graphic_eq_rounded,
              title: '播放音质',
              value: player.quality.label,
              onTap: () => _pickQuality(player),
            ),
          ]),
          _sectionTitle('音乐源'),
          _card([
            _row(
              icon: Icons.language_rounded,
              title: '当前音乐源',
              value: _platform.isEmpty ? '未选择' : _platform,
              onTap: _pickPlatform,
            ),
            _divider(),
            _row(
              icon: Icons.sync_rounded,
              title: '同步音源',
              value: _syncing ? '同步中…' : '${_platforms.length} 个可用',
              onTap: _syncing ? null : _sync,
            ),
          ]),
          if (_platforms.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Text(
                '暂无音源，点击「同步音源」从服务端获取',
                style: TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ),
          _sectionTitle('安装包'),
          _card([
            _row(
              title: '当前版本',
              value: kAppVersion,
            ),
            _divider(),
            _row(
              title: '下载最新安装包',
              value: _downloading ? '获取中…' : _updateLabel,
              onTap: _downloading ? null : _downloadLatest,
            ),
            if (_ipaBytes > 0) ...[
              _divider(),
              _row(
                title: '删除已下载安装包',
                value:
                    '${(_ipaBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                onTap: _clearIpaCache,
                danger: true,
              ),
            ],
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(
              '安装包会保存在 App 内，安装后不会自动删除，可在此手动清理',
              style: TextStyle(fontSize: 11, color: AppColors.text3),
            ),
          ),
          _sectionTitle('账户'),
          _card([
            _row(
              icon: Icons.logout,
              title: '退出登录',
              danger: true,
              onTap: _logout,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 50,
      endIndent: 14,
      color: AppColors.border,
    );
  }

  Widget _row({
    IconData? icon,
    required String title,
    String? value,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF7A93) : AppColors.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 20,
                  color: danger ? const Color(0xFFFF7A93) : AppColors.text2),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
            if (value != null) ...[
              Text(
                value,
                style:
                    TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.text3),
            ],
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'music' => '歌曲',
      'album' => '专辑',
      'artist' => '歌手',
      'sheet' => '歌单',
      _ => type,
    };
  }

}

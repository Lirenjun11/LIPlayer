# 音乐播放器 (Flutter)

跨平台（iOS / Android）音乐播放器，功能与 `tvlive/pages/music/musicfree.vue` 对齐，
后端接口沿用同一套 `https://m.lrj.ccwu.cc/` 服务：

- 登录页（`POST api/auth/login`，服务端下发 `musicplayer_auth` Cookie，后续请求自动携带）
- 发现页：排行榜（多分组）+ 热门歌单
- 搜索页：关键词搜索、分页加载、加入队列
- 队列页 / 队列面板
- 迷你播放栏 + 全屏播放器（旋转封面、LRC 歌词滚动、进度拖动）
- 播放模式：顺序 / 随机 / 单曲循环
- 后台播放与锁屏控制（`just_audio` + `just_audio_background`）
- 播放状态本地持久化（`shared_preferences`）

## 目录结构

```
lib/
├─ main.dart                 入口，初始化后台音频 + Provider
├─ app.dart                  MaterialApp + 登录态路由
├─ theme.dart                深色主题 / 配色
├─ models/                   Song / MusicPlatform / MusicCollection / LyricLine
├─ services/api_service.dart 登录鉴权 + 所有 api/external/* 接口
├─ state/
│   ├─ auth_state.dart       登录态
│   └─ player_state.dart     播放引擎（just_audio 封装）
├─ screens/
│   ├─ login_screen.dart     登录页
│   ├─ home_screen.dart      发现/搜索/队列 + 迷你播放
│   └─ full_player_screen.dart 全屏播放器
├─ widgets/                  封面、歌曲行、音源选择、迷你播放、队列面板
└─ utils/format.dart         时间/计数格式化
```

## 快速开始

> 需要 Flutter `>= 3.27`（用到 `Color.withValues`）与 Dart `>= 3.3`。

本仓库只包含 Dart 源码与 `pubspec.yaml`，平台工程需用 `flutter create` 生成。

```bash
# 1) 在项目根目录补全 ios / android 平台工程（不会覆盖已存在的 lib/ 文件）
flutter create --platforms=android,ios --org com.example --project-name musicplayer .

# 2) 安装依赖
flutter pub get

# 3) 运行
flutter run
```

### 平台配置（后台播放 / 锁屏控制必需）

`just_audio_background` 需要在原生工程做少量配置。

**Android** — `android/app/src/main/AndroidManifest.xml`

在 `<application>` 内加入：

```xml
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
  <intent-filter>
    <action android:name="android.media.browse.MediaBrowserService" />
  </intent-filter>
</service>
<receiver
    android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON" />
  </intent-filter>
</receiver>
```

并在 `<manifest>` 下（`<application>` 之前）加入权限：

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

`MainActivity`（`android/app/src/main/kotlin/.../MainActivity.kt`）改为继承 `AudioServiceActivity`：

```kotlin
package com.example.musicplayer

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
```

**iOS** — `ios/Runner/Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## 后端接口

| 用途 | 接口 |
|---|---|
| 登录 | `POST api/auth/login` → Set-Cookie `musicplayer_auth` |
| 音源列表 | `GET api/external/plugins` |
| 榜单分组 | `GET api/external/toplist?platform=` |
| 分组明细 | `GET api/external/toplist-group?platform=&group=` |
| 榜单详情 | `GET api/external/toplist-detail?platform=&id=` |
| 热门歌单 | `GET api/external/sheets?platform=&tag=热门&page=` |
| 歌单详情 | `GET api/external/sheet-detail?platform=&id=` |
| 搜索 | `GET api/external/search?platform=&keyword=&page=&type=music` |
| 播放地址 | `GET api/external/play-url?platform=&id=&quality=standard` |
| 歌曲详情 | `GET api/external/song-detail?platform=&id=` |
| 歌词 | `GET api/external/lyric?platform=&id=` |

统一响应：`{ "code": 0, "data": ... }`；`401` 视为登录失效并回到登录页。

## iOS 无证书 / 越狱构建

见 `.github/workflows/ios-unsigned.yml`：在 GitHub Actions 的 macOS runner 上执行
`flutter build ios --no-codesign` → `ldid -S` 伪签名 → 打包 `Payload/*.ipa` 并上传为产物，
无需任何证书，产物可经 TrollStore / AppSync 安装到越狱设备。

本地等价命令（macOS）：

```bash
flutter build ios --release --no-codesign
brew install ldid
mkdir -p Payload && cp -r build/ios/iphoneos/Runner.app Payload/
ldid -S Payload/Runner.app/Runner
zip -qr MusicPlayer.ipa Payload
```

# GuoPlayer for iPhone and iPad

## 1.1.1 (4) 修复

详情页海报背景现在固定在设备宽度内，避免横向撑开导致文字和按钮只显示一半。播放资源收进一个可点击的选择入口，剧集选集改为横向滑动卡片，同一集在多个服务器上会先让用户选择片源。底部导航贴住屏幕底部；首页 Banner、媒体横排与剧集卡片均可横向滑动，屏幕边缘滑动可切换主栏目或返回详情。播放器会判断 Apple 设备可直接播放的编码，在播放失败或连接超时时尝试 Emby HLS 转码，并在画面中央显示失败原因。以上播放修复已通过编译和 URL 检查，仍需在实际 Emby 服务器与真机上复测。

[1.1.1 (4) 未签名 IPA 构建](https://github.com/guozexian110/GuoPlayer-iOS/actions/runs/36280497468)的 `GuoPlayer-unsigned-ipa` Artifact 可用于重新签名安装。

原生 SwiftUI + AVFoundation 工程：`GuoPlayer.xcodeproj`。最低 iOS/iPadOS 17，默认 Bundle ID 为 `com.guoplayer.app`，可在 Xcode 的 Target → Signing & Capabilities 修改。工程没有 Team ID、证书、Provisioning Profile、Apple ID 或内置媒体源。

## 使用和范围

在「设置」添加自己的 Emby 地址、用户名和密码。密码只用于本次登录；Token 写入 Keychain。首页读取真实媒体库、续播、最近添加、电影和剧集；搜索跨服务器查询；详情聚合相同 Provider ID 的作品，并列出各服务器片源。剧集读取真实季集。播放器请求 PlaybackInfo，MP4/MOV 优先 Direct Play，其余容器优先使用 Emby HLS 转码；支持源、音轨、字幕索引、倍速、拖动、快进退、画中画，以及开始/进度/停止上报。可用轨道、编码、转码能力取决于设备和各自的 Emby 服务器。

发现页优先显示媒体自身的 Emby 背景与海报。用户需有权访问自己的服务器内容。为支持用户自行输入 LAN HTTP 地址，Info.plist 放开了 ATS；建议远程服务器使用 HTTPS。播放与图片 URL 含 Emby Token，是 AVPlayer 无法统一附带 Emby 自定义请求头时的兼容方式；请勿共享含令牌的 URL。

界面采用 GuoPlayer 自己的蓝青 Logo，参考用户录屏中的页面分布：全屏背景 Banner、横向继续观看和推荐媒体行、分类与服务器卡片、悬浮底栏，以及详情页的评分、画质筛选、片源卡片和演职人员区。影片图片和文字只取自用户添加的 Emby 服务器。iOS 启动屏与 AppIcon 已配置；[模拟器截图构建](https://github.com/guozexian110/GuoPlayer-iOS/actions/runs/36241543773)通过 iPhone 与 iPad 启动截图验证，截图可在该运行的 `GuoPlayer-simulator-screenshots` Artifact 下载。布局会随可用屏幕宽度调整，最低系统要求仍为 iOS/iPadOS 17。

## GitHub Actions：获取未签名 IPA

仓库地址：[guozexian110/GuoPlayer-iOS](https://github.com/guozexian110/GuoPlayer-iOS)。在仓库 **Actions → iOS unsigned build → Run workflow**，或推送 `iOS/` 改动触发。构建成功后，在该次运行页面底部 **Artifacts → GuoPlayer-unsigned-ipa** 下载压缩包；其中是 `GuoPlayer-unsigned.ipa`。[1.1.1 (4) IPA 构建](https://github.com/guozexian110/GuoPlayer-iOS/actions/runs/36280497468)已上传该 Artifact。IPA 由 `Payload/GuoPlayer.app` 打包，不含签名。2026-09-27 的 GitHub Hosted macOS 构建已通过模拟器 Debug 和设备 Release 编译、静态检查、聚合逻辑与播放 URL 测试；IPA 的 ZIP 结构、Bundle ID 和无签名状态已检查。

下载的 IPA 不能直接安装。Sideloadly、AltStore/SideStore 等工具可以用使用者自己的免费 Apple ID 重新签名并安装。按各工具提示在本机完成 Apple ID 验证，不要把密码、验证码或私钥提交到项目或 Actions。免费 Personal Team 自签通常有有效期和应用数量限制；免费 GitHub Hosted macOS 分钟也受仓库类型及账户配额限制，不保证所有账户无限零成本。

## 将来在 Mac 本地构建

用 Xcode 16 或更新版本打开 `iOS/GuoPlayer.xcodeproj`，选择 GuoPlayer Target，在 Signing & Capabilities 中选择自己的 Personal Team，必要时改 Bundle ID，连接 iPhone/iPad 后运行。项目没有 App Groups、Push、iCloud 或 Associated Domains 权限要求。未签名本地构建命令：

```sh
xcodebuild -project iOS/GuoPlayer.xcodeproj -scheme GuoPlayer -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## 已知限制

当前尚未在真实 iPhone/iPad 或用户的 Emby 服务器上验证。对于非 Apple 原生支持的容器，Emby 需要允许 HLS 转码。外挂字幕需要服务器提供可转码字幕轨道；内嵌轨道也取决于 AVPlayer 或转码结果。没有实现离线下载、弹幕、跨服务器进度双向同步。服务器媒体库大于首页第一页时，需要在资源库选中具体媒体库；尚无全库持续分页索引。

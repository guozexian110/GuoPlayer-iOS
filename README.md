# GuoPlayer for iPhone and iPad

## 1.1.6 (9) 零成本首页回退

发现首页默认展示用户已连接的 Emby 内容，每次打开和回到前台刷新。个人用户可选填自己的免费 TMDb 凭据，在自己的设备上启用 TMDb 发现页；未填写时不出现空白的 TMDb 配置页。

TMDb 的申请页面将向其他用户公开供数的用途导向商业订阅。为遵守零成本目标，仓库不再运行公开 TMDb 数据源；不要把个人免费 Token 放进面向所有用户的共享服务。若 TMDb 将来书面允许免费开源公开使用，可再接入经授权的数据源。

## 1.1.4 (7) 今日动漫

「今日动漫」取 TMDb 当天播出的剧集，并筛选动画类型；当天没有结果时该行不显示。

## 1.1.3 (6) 播放路径修复

针对真机播放报 HTTP 404，播放器现在会对服务器视频 URL 依次尝试 `/emby/Videos/...` 和 `/Videos/...`，保留原请求的片源、音轨、字幕及认证参数；服务端返回的转码 URL 仍优先使用。该修复需要用用户的真实 Emby 服务器复测，云端编译和 URL 测试不能证明所有服务器均可播放。

## 1.1.2 (5) TMDb 发现首页

发现页按精选卡、今日趋势、本周趋势、热门电影与剧集、正在热映、今日动漫、播出平台、分类浏览、电影公司和高分榜单排列。影视条目、海报和简介从 TMDb API 读取；平台和电影公司模块使用 TMDb 筛选条件。每次启动、返回前台或下拉刷新时重新请求。点开条目后，若 TMDb ID 与 Emby 媒体库的 ProviderIds 匹配，可进入真实片源详情；没有片源时会明确提示。界面采用 GuoPlayer 自己的样式，不包含参考 App 的素材。

个人凭据可在设置中输入，仅保存在本机 Keychain；未配置时首页使用 Emby 数据。TMDb 资料归 TMDb 及相应权利人所有，本应用未获得其认可或背书。

## 1.1.1 (4) 修复

详情页海报背景现在固定在设备宽度内，避免横向撑开导致文字和按钮只显示一半。播放资源收进一个可点击的选择入口，剧集选集改为横向滑动卡片，同一集在多个服务器上会先让用户选择片源。底部导航贴住屏幕底部；首页 Banner、媒体横排与剧集卡片均可横向滑动，屏幕边缘滑动可切换主栏目或返回详情。播放器会判断 Apple 设备可直接播放的编码，在播放失败或连接超时时尝试 Emby HLS 转码，并在画面中央显示失败原因。以上播放修复已通过编译和 URL 检查，仍需在实际 Emby 服务器与真机上复测。

[1.1.1 (4) 未签名 IPA 构建](https://github.com/guozexian110/GuoPlayer-iOS/actions/runs/36280497468)的 `GuoPlayer-unsigned-ipa` Artifact 可用于重新签名安装。

原生 SwiftUI + AVFoundation 工程：`GuoPlayer.xcodeproj`。最低 iOS/iPadOS 17，默认 Bundle ID 为 `com.guoplayer.app`，可在 Xcode 的 Target → Signing & Capabilities 修改。工程没有 Team ID、证书、Provisioning Profile、Apple ID 或内置媒体源。

## 使用和范围

在「设置」添加自己的 Emby 地址、用户名和密码。密码只用于本次登录；Token 写入 Keychain。首页读取真实媒体库、续播、最近添加、电影和剧集；搜索跨服务器查询；详情聚合相同 Provider ID 的作品，并列出各服务器片源。剧集读取真实季集。播放器请求 PlaybackInfo，MP4/MOV 优先 AVPlayer Direct Play，MKV、FLAC、TrueHD 等使用 VLC 原片直放，必要且服务器允许时使用 Emby HLS 转码；支持源、音轨、字幕索引、倍速、拖动、快进退、画中画，以及开始/进度/停止上报。可用轨道、编码、转码能力取决于设备和各自的 Emby 服务器。

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

当前尚未在真实 iPhone/iPad 或用户的 Emby 服务器上验证。MKV 和非 Apple 音轨通过 VLC 本地解码；无需服务器转码权限。VLC 支持内嵌字幕和 Emby 提供的外挂字幕；AVPlayer 路径仍支持画中画，VLC 路径尚无画中画。外挂字幕需要服务器提供可转码字幕轨道；内嵌轨道也取决于 AVPlayer 或转码结果。没有实现离线下载、弹幕、跨服务器进度双向同步。服务器媒体库大于首页第一页时，需要在资源库选中具体媒体库；尚无全库持续分页索引。


### 1.1.7 (10)

- TMDb 首页热门电影支持滑动轮播，今日与本周趋势采用横向背景海报、标题和年份卡片。需个人 TMDb 凭据；截图里的 Forward Widgets 不是本项目可调用的数据接口。
- Emby PlaybackInfo 提交 AVFoundation DeviceProfile，协商 MP4 Direct Play 与 H.264/AAC HLS 转码。使用服务器返回的 origin-relative 视频地址，404 时尝试 Emby 路径兼容地址。
- 静态播放使用 Emby /Videos/{id}/stream，避免依赖服务器对 stream.{container} 的兼容；播放切换保持进度，取消旧进度任务。
- PlaybackSmoke 通过模拟 HTTP 测试能力协商、404 API 回退、视频 URL 和进度上报。模拟测试不代表实际 Emby 服务器或 iPhone 已播放成功。
- 新提供的视频文件在指定位置不可读取，视频页面与动画仍待补充核对。


### 1.1.8 (11)

已读取用户提供的桌面录屏并按模块顺序实现沉浸式顶部轮播、继续观看、横向趋势卡片、热门电影大卡、热映和动漫海报、平台拼贴卡片、分类、电影公司和高分榜。分类详情页包含宽幅精选和自适应海报网格。首页编辑支持模块顺序、显示开关、轮播来源与趋势标题/榜单选择，配置保存在本机。播出平台资料来自 TMDb 的美国区域可用性列表，不能当作平台原创名单。

macOS CI 截图使用 --layout-preview 的虚构内容检查排版，仅 Debug 构建有此入口；Release 使用真实 Emby/TMDb 数据，不包含预览内容。播放测试保留 1.1.7 的 HTTP AVPlayer 与 Emby 协议检查。真实用户服务器播放尚待验证。


### 1.1.9 (12)

添加与编辑服务器支持独立端口栏，保留旧地址中的端口和子路径；显式端口优先，校验 1–65535，支持 IPv6。API 成功后记住服务器可用路径，播放沿用该路径；服务器返回 /Videos 地址时尝试包含代理子路径的候选地址。播放前使用 GET Range 检查响应头并立即取消下载，拒绝 404 和网页响应，再尝试下一个地址。服务器返回的外部签名 URL 不附加 Emby Token 或修改参数。新增缺失子路径导致 404 的实际 HTTP AVPlayer 集成测试，覆盖协商、地址回退、播放、拖动与进度上报。播放故障提示显示实际 HTTP 状态；真实用户服务器仍需要复测。


### 1.2.0 (15): MKV 原片播放

真实服务器诊断发现原始文件 HTTP 206、HEVC/MKV 搭配 FLAC 或 TrueHD，但用户策略禁止视频及音频转码。旧版 AVPlayer 原片与转码回退均不适用。新版按容器/编码选择 VLC 原片播放；原生格式保留 AVPlayer，失败时先试 VLC，再在服务器确实提供 TranscodingUrl 时回退转码。VLC 音轨及内嵌字幕使用实际播放器 track ID，外挂字幕使用 Emby DeliveryUrl 或字幕下载接口，本地切换，不向服务器要求烧录字幕或转换音轨。支持播放/暂停、续播、拖动、倍速、快进退和剧集自动下一集，沿用 Emby 进度上报。

依赖固定为 VLCKit-SPM 3.6.0，SPM 校验二进制 SHA256，无 Apple Team 或证书。许可及替换/重新链接说明见 iOS/THIRD_PARTY_NOTICES.md。CI 新增 iPhone 模拟器 MKV/HEVC + 双 FLAC 音轨 + SRT 字幕的真实解码、画面输出、音轨/字幕选择、拖动与暂停续播检查；不是只判断 HTTP 200。真实 iPhone 尚待安装后验证，不把模拟器结果当作用户真机播放成功。

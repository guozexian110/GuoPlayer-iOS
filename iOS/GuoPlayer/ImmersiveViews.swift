import SwiftUI

private let canvas = Color(red: 0.035, green: 0.065, blue: 0.10)
private let accent = Color(red: 0.15, green: 0.84, blue: 0.91)

struct FloatingNavigationBar: View {
    @EnvironmentObject private var chrome: AppChrome

    var body: some View {
        HStack(spacing: 0) {
            Button { chrome.showingSettings = true } label: {
                Image("BrandMark").resizable().scaledToFit().frame(width: 34, height: 34).clipShape(Circle())
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("服务器与账户")
            tab("发现", icon: "play.rectangle.fill", index: 0)
            tab("资源库", icon: "square.stack.fill", index: 1)
            Button { chrome.showingSettings = true } label: {
                VStack(spacing: 2) { Image(systemName: "gearshape.fill").font(.system(size: 20)); Text("设置").font(.system(size: 10)) }
                    .foregroundStyle(.white.opacity(0.75)).frame(maxWidth: .infinity, minHeight: 48)
            }
            tab("搜索", icon: "magnifyingglass", index: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background(canvas.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }

    private func tab(_ title: String, icon: String, index: Int) -> some View {
        Button { chrome.selectedTab = index } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(chrome.selectedTab == index ? accent : .white.opacity(0.68))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityAddTraits(chrome.selectedTab == index ? [.isSelected] : [])
    }
}

struct ImmersiveDiscoverView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var chrome: AppChrome
    @State private var heroIndex = 0

    private var featured: [MediaGroup] { Array(store.groups.prefix(8)) }
    private var topRated: [MediaGroup] {
        store.groups.filter { $0.primary.communityRating != nil }
            .sorted { ($0.primary.communityRating ?? 0) > ($1.primary.communityRating ?? 0) }
    }

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = min(max(geometry.size.width * 1.36, 470), 670)
            ScrollView {
                VStack(spacing: 0) {
                    if featured.isEmpty {
                        emptyHero(height: heroHeight)
                    } else {
                        ZStack(alignment: .bottom) {
                            TabView(selection: $heroIndex) {
                                ForEach(featured.indices, id: \.self) { index in
                                    NavigationLink { ImmersiveDetailView(group: featured[index]) } label: {
                                        DiscoveryHero(group: featured[index], width: geometry.size.width, height: heroHeight)
                                    }.buttonStyle(.plain).tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            HStack(spacing: 5) {
                                ForEach(featured.indices, id: \.self) { index in
                                    Circle().fill(index == heroIndex ? Color.white : Color.white.opacity(0.45))
                                        .frame(width: index == heroIndex ? 7 : 5, height: index == heroIndex ? 7 : 5)
                                }
                            }.padding(.bottom, 11)
                        }.frame(height: heroHeight)
                    }

                    VStack(alignment: .leading, spacing: 27) {
                        WideMediaRail(title: "继续观看", groups: store.resumeGroups, showsProgress: true)
                        WideMediaRail(title: "今日推荐", groups: Array(store.groups.prefix(20)))
                        WideMediaRail(title: "本周热播", groups: Array(topRated.prefix(20)))
                        if let spotlight = store.groups.first(where: { $0.primary.type == "Movie" }) {
                            DiscoverySpotlight(group: spotlight)
                        }
                        WideMediaRail(title: "最近添加", groups: Array(store.groups.prefix(20)))
                        WideMediaRail(title: "电视剧与动漫", groups: store.groups.filter { $0.primary.type == "Series" })
                        if !store.servers.isEmpty { serverRail }
                        categoryRail
                        if !topRated.isEmpty { rankedRail }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await store.refresh() }
            .ignoresSafeArea(edges: .top)
        }
        .background(canvas)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let error = store.error {
                Text(error).font(.caption).padding(9).background(.red.opacity(0.85), in: Capsule())
                    .padding(.top, 70).padding(.horizontal)
            }
        }
    }

    private func emptyHero(height: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.06, green: 0.31, blue: 0.39), canvas], center: .top, startRadius: 10, endRadius: height)
            VStack(spacing: 15) {
                Spacer(minLength: 65)
                Image("BrandMark").resizable().scaledToFit().frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 25))
                Text("GuoPlayer").font(.largeTitle.bold())
                Text("连接你的 Emby，发现属于你的片单")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button { chrome.showingSettings = true } label: {
                    Label("添加 Emby 服务器", systemImage: "plus")
                        .font(.headline).padding(.horizontal, 22).padding(.vertical, 12)
                        .background(accent, in: Capsule()).foregroundStyle(.black)
                }.padding(.top, 8)
                Spacer(minLength: 35)
            }.padding(.horizontal, 24)
        }.frame(height: height)
    }

    private var serverRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowTitle("我的服务器")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.servers) { server in
                        Button { chrome.showingSettings = true } label: {
                            HStack(spacing: 12) {
                                Image("BrandMark").resizable().scaledToFit().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(server.name).font(.subheadline.bold()).lineLimit(1)
                                    Text("Emby 片源").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: 208).padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowTitle("分类浏览")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    category("最新电影", icon: "film", value: "Movie")
                    category("剧集与动漫", icon: "tv", value: "Series")
                    category("我的收藏", icon: "heart", value: "Favorite")
                }.padding(.horizontal, 16)
            }
        }
    }

    private func category(_ title: String, icon: String, value: String) -> some View {
        Button {
            chrome.libraryCategory = value
            chrome.selectedTab = 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(accent)
                Text(title).font(.subheadline.bold()).lineLimit(1)
            }
            .frame(width: 150, height: 62)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var rankedRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowTitle("高分作品")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 11) {
                    ForEach(Array(topRated.prefix(6).enumerated()), id: \.offset) { rank, group in
                        NavigationLink { ImmersiveDetailView(group: group) } label: {
                            HStack(alignment: .bottom, spacing: 6) {
                                Text("\(rank + 1)").font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.66))
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(item: group.primary, width: 104)
                                    Text(String(format: "%.1f ★", group.primary.communityRating ?? 0))
                                        .font(.caption).foregroundStyle(accent)
                                }
                            }
                            .padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    private func rowTitle(_ title: String) -> some View {
        HStack { Text(title).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
            .padding(.horizontal, 16)
    }
}

private struct DiscoveryHero: View {
    @EnvironmentObject private var store: AppStore
    let group: MediaGroup
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: store.poster(group.primary, backdrop: true) ?? store.poster(group.primary)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [Color(red: 0.10, green: 0.38, blue: 0.47), canvas], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: width, height: height).clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0), .init(color: canvas.opacity(0.20), location: 0.42), .init(color: canvas.opacity(0.82), location: 0.73), .init(color: canvas, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 9) {
                Text("GUOPLAYER · 为你发现").font(.caption2.bold()).tracking(2).foregroundStyle(accent)
                Text(group.title).font(.system(size: 34, weight: .bold)).lineLimit(2).minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                Text("\(group.primary.year.map(String.init) ?? "")  ·  \(group.primary.type == "Movie" ? "电影" : "剧集")  ·  \(group.variants.count) 个片源")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                if let overview = group.primary.overview, !overview.isEmpty {
                    Text(overview).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 25)
                }
                if let rating = group.primary.communityRating {
                    Text(String(format: "★ %.1f", rating)).font(.caption.bold()).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 38)
        }
        .frame(width: width, height: height).clipped()
        .accessibilityLabel("\(group.title)，查看详情")
    }
}

private struct WideMediaRail: View {
    @EnvironmentObject private var chrome: AppChrome
    let title: String
    let groups: [MediaGroup]
    var showsProgress = false

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Button { chrome.selectedTab = 1 } label: {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 16)
                }.buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(groups) { group in WideMediaCard(group: group, showsProgress: showsProgress) }
                    }.padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct WideMediaCard: View {
    @EnvironmentObject private var store: AppStore
    let group: MediaGroup
    let showsProgress: Bool

    var body: some View {
        NavigationLink { ImmersiveDetailView(group: group) } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: store.poster(group.primary, backdrop: true) ?? store.poster(group.primary)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Color.white.opacity(0.08) }
                    .frame(width: 190, height: 108).clipped()
                    if showsProgress && group.primary.progress > 0 {
                        GeometryReader { g in
                            Rectangle().fill(accent).frame(width: g.size.width * group.primary.progress, height: 3)
                        }.frame(height: 3)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 11))
                Text(group.title).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 190, alignment: .leading)
                Text(group.primary.year.map(String.init) ?? "\(group.variants.count) 个片源")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 190, alignment: .leading)
        }.buttonStyle(.plain)
    }
}

private struct DiscoverySpotlight: View {
    @EnvironmentObject private var store: AppStore
    let group: MediaGroup

    var body: some View {
        NavigationLink { ImmersiveDetailView(group: group) } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: store.poster(group.primary, backdrop: true) ?? store.poster(group.primary)) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color(red: 0.10, green: 0.26, blue: 0.34) }
                .frame(height: 210).frame(maxWidth: .infinity).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text("热门电影").font(.caption.bold()).tracking(2)
                    Text(group.title).font(.title2.bold()).lineLimit(1)
                }.padding(16)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .padding(.horizontal, 16)
        }.buttonStyle(.plain)
    }
}

private struct SourceChoice: Identifiable {
    let item: MediaItem
    let source: PlaybackSource
    var id: String { "\(item.serverId):\(item.id):\(source.id)" }
}

struct ImmersiveDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var chrome: AppChrome
    @Environment(\.dismiss) private var dismiss
    let group: MediaGroup
    @State private var playbackInfo: [MediaItem: PlaybackInfo] = [:]
    @State private var episodes: [MediaItem] = []
    @State private var selectedSeason: Int?
    @State private var selectedServer: UUID?
    @State private var selectedQuality = "全部"
    @State private var showingTechnicalInfo = false
    @State private var showingSourcePicker = false
    @State private var showingEpisodeSourcePicker = false
    @State private var episodeChoices: [MediaItem] = []
    @State private var pendingPlayback: MediaItem?
    @State private var playing: MediaItem?
    @State private var preferredSourceId: String?

    private var choices: [SourceChoice] {
        group.variants.flatMap { item in
            (playbackInfo[item]?.mediaSources ?? []).map { SourceChoice(item: item, source: $0) }
        }
    }
    private var visibleChoices: [SourceChoice] { selectedQuality == "全部" ? choices : choices.filter { $0.source.resolutionLabel == selectedQuality } }
    private var similar: [MediaGroup] {
        Array(store.groups.filter { $0.id != group.id && $0.primary.type == group.primary.type }.prefix(12))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(width: geometry.size.width, height: min(max(geometry.size.width * 1.26, 430), 650))
                        VStack(alignment: .leading, spacing: 22) {
                            HStack(spacing: 42) {
                                Button { withAnimation { scroll.scrollTo("sources", anchor: .top) } } label: { action("片源", icon: "play.rectangle.on.rectangle") }
                                Button { Task { await store.toggleFavorite(group.primary) } } label: { action(group.isFavorite ? "已收藏" : "收藏", icon: group.isFavorite ? "heart.fill" : "heart") }
                                Button { showingTechnicalInfo.toggle() } label: { action("信息", icon: "info.circle") }
                            }.frame(maxWidth: .infinity)
                            if let overview = group.primary.overview, !overview.isEmpty {
                                Text(overview).font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(showingTechnicalInfo ? nil : 4)
                            }
                            HStack(spacing: 12) {
                                if let rating = group.primary.communityRating {
                                    Text(String(format: "★ %.1f", rating)).foregroundStyle(accent)
                                }
                                if let year = group.primary.year { Text(String(year)) }
                                Text(group.primary.isSeries ? "剧集" : "电影")
                                Text("\(group.variants.count) 个服务器")
                            }.font(.caption).foregroundStyle(.white.opacity(0.75))
                            if showingTechnicalInfo { technicalInfo }
                            sourceSection.id("sources")
                            if group.primary.isSeries { episodeSection }
                            if !group.primary.people.isEmpty { peopleSection }
                            if !similar.isEmpty { WideMediaRail(title: "相似作品", groups: similar) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 110)
                        .frame(maxWidth: 930)
                        .frame(maxWidth: .infinity)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .frame(width: geometry.size.width)
            }
        }
        .background(canvas)
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
            if value.startLocation.x < 30 && value.translation.width > 100 && abs(value.translation.height) < 70 { dismiss() }
        })
        .onAppear { chrome.hidesNavigation = true }
        .onDisappear { chrome.hidesNavigation = false }
        .task { await loadDetails() }
        .sheet(isPresented: $showingSourcePicker, onDismiss: startPendingPlayback) { sourcePicker }
        .sheet(isPresented: $showingEpisodeSourcePicker, onDismiss: startPendingPlayback) { episodeSourcePicker }
        .fullScreenCover(item: $playing) { item in
            PlayerView(item: item, playlist: episodes.filter { $0.serverId == item.serverId }
                .sorted { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }, preferredSourceId: preferredSourceId)
        }
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: store.poster(group.primary, backdrop: true) ?? store.poster(group.primary)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [Color(red: 0.10, green: 0.34, blue: 0.42), canvas], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: width, height: height).clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0), .init(color: canvas.opacity(0.20), location: 0.45), .init(color: canvas.opacity(0.8), location: 0.79), .init(color: canvas, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 11) {
                Text(group.title).font(.system(size: 34, weight: .bold)).lineLimit(2).minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                Text("\(group.primary.year.map(String.init) ?? "")  ·  \(group.primary.isSeries ? "剧集" : "电影")")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Button { playPrimary() } label: {
                    Label(group.primary.progress > 0 ? "继续播放" : "播放", systemImage: "play.fill")
                        .font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: width, height: height).clipped()
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }.buttonStyle(.plain).padding(.leading, 16).padding(.top, 58)
        }
    }

    private func action(_ label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.title3)
            Text(label).font(.caption2)
        }.foregroundStyle(.white.opacity(0.86))
    }

    private var technicalInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("媒体信息").font(.caption.bold())
            ForEach(group.primary.providerIds.keys.sorted(), id: \.self) { key in
                Text("\(key): \(group.primary.providerIds[key] ?? "")").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("播放资源").font(.headline)
            Button { showingSourcePicker = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.primary.isSeries ? "选择服务器片源" : "选择播放资源").font(.subheadline.bold())
                        Text(group.primary.isSeries ? "\(group.variants.count) 个服务器 · 选集后播放" : "\(choices.isEmpty ? group.variants.count : choices.count) 个片源 · 点击选择")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
            if !choices.isEmpty {
                Button { showingTechnicalInfo.toggle() } label: {
                    Label(showingTechnicalInfo ? "收起媒体信息" : "展开媒体信息", systemImage: "chevron.down")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
    }

    private var sourcePicker: some View {
        NavigationStack {
            List {
                if !group.primary.isSeries && !choices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["全部", "4K", "1080P", "720P"], id: \.self) { quality in
                                if quality == "全部" || choices.contains(where: { $0.source.resolutionLabel == quality }) {
                                    Button(quality) { selectedQuality = quality }
                                        .font(.caption.bold()).padding(.horizontal, 15).padding(.vertical, 8)
                                        .background(selectedQuality == quality ? accent.opacity(0.3) : .white.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }.listRowBackground(Color.clear)
                    ForEach(visibleChoices) { choice in
                        Button {
                            showingSourcePicker = false
                            preferredSourceId = choice.source.id
                            pendingPlayback = choice.item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(choice.source.resolutionLabel) · \(store.server(for: choice.item)?.name ?? "Emby")").font(.headline)
                                    Text("\(choice.source.container?.uppercased() ?? "视频") · \(choice.source.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "大小未知")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").foregroundStyle(accent)
                            }
                        }.foregroundStyle(.primary)
                    }
                } else {
                    ForEach(group.variants) { item in
                        Button {
                            showingSourcePicker = false
                            if group.primary.isSeries { selectedServer = item.serverId }
                            else { preferredSourceId = nil; pendingPlayback = item }
                        } label: {
                            HStack {
                                Label(store.server(for: item)?.name ?? "Emby", systemImage: "server.rack")
                                Spacer()
                                Image(systemName: group.primary.isSeries ? "checkmark.circle" : "play.circle.fill").foregroundStyle(accent)
                            }
                        }.foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("选择片源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { showingSourcePicker = false } }
        }.presentationDetents([.medium, .large])
    }

    private var episodeGroups: [[MediaItem]] {
        let filtered = episodes.filter { (selectedSeason == nil || $0.parentIndexNumber == selectedSeason) && (selectedServer == nil || $0.serverId == selectedServer) }
        let groups = Dictionary(grouping: filtered) { episode in
            episode.indexNumber.map { "\(episode.parentIndexNumber ?? -1):\($0)" } ?? "\(episode.serverId):\(episode.id)"
        }
        return groups.values.sorted {
            let a = $0[0], b = $1[0]
            return (a.parentIndexNumber ?? 0, a.indexNumber ?? 0) < (b.parentIndexNumber ?? 0, b.indexNumber ?? 0)
        }
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("选集").font(.headline)
            if !group.variants.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("全部片源") { selectedServer = nil }
                        ForEach(group.variants) { item in
                            Button(store.server(for: item)?.name ?? "Emby") { selectedServer = item.serverId }
                        }
                    }.font(.caption).buttonStyle(.bordered)
                }
            }
            let seasons = Array(Set(episodes.compactMap(\.parentIndexNumber))).sorted()
            if !seasons.isEmpty {
                Picker("季", selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { season in
                        Text(season == 0 ? "特别篇" : "第\(season)季").tag(Optional(season))
                    }
                }.pickerStyle(.menu)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(episodeGroups.enumerated()), id: \.offset) { _, variants in
                        let episode = variants[0]
                        Button {
                            if variants.count > 1 {
                                episodeChoices = variants
                                showingEpisodeSourcePicker = true
                            } else {
                                preferredSourceId = nil
                                playing = episode
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: store.poster(episode) ?? store.poster(group.primary, backdrop: true)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { Color.white.opacity(0.08) }
                                .frame(width: 210, height: 118).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                                Text("第 \(episode.indexNumber ?? 0) 集 · \(episode.name)")
                                    .font(.subheadline.bold()).lineLimit(1)
                                Text(variants.count > 1 ? "\(variants.count) 个服务器" : (store.server(for: episode)?.name ?? "Emby"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 210, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var episodeSourcePicker: some View {
        NavigationStack {
            List(episodeChoices) { episode in
                Button {
                    showingEpisodeSourcePicker = false
                    preferredSourceId = nil
                    pendingPlayback = episode
                } label: {
                    HStack {
                        Label(store.server(for: episode)?.name ?? "Emby", systemImage: "server.rack")
                        Spacer()
                        Image(systemName: "play.circle.fill").foregroundStyle(accent)
                    }
                }.foregroundStyle(.primary)
            }
            .navigationTitle("选择这一集的片源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { showingEpisodeSourcePicker = false } }
        }.presentationDetents([.medium, .large])
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("演职人员").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 13) {
                    ForEach(Array(group.primary.people.prefix(15).enumerated()), id: \.offset) { _, person in
                        VStack(spacing: 5) {
                            AsyncImage(url: personImageURL(person)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ZStack { Circle().fill(.white.opacity(0.12)); Text(String(person.name.prefix(1))).font(.title2) }
                            }
                            .frame(width: 63, height: 63).clipShape(Circle())
                            Text(person.name).font(.caption2).lineLimit(1)
                            Text(person.role ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(width: 74)
                    }
                }
            }
        }
    }

    private func personImageURL(_ person: MediaPerson) -> URL? {
        guard let id = person.id, person.primaryImageTag != nil,
              let server = store.server(for: group.primary), let token = TokenVault.read(server.id) else { return nil }
        return store.api.url(server, "Persons/\(id)/Images/Primary", query: ["api_key": token, "maxWidth": "150"])
    }

    private func playPrimary() {
        if group.primary.isSeries {
            guard let first = episodes.sorted(by: { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }).first else { return }
            preferredSourceId = nil
            playing = first
        } else {
            preferredSourceId = nil
            playing = group.primary
        }
    }

    private func startPendingPlayback() {
        if let pendingPlayback {
            self.pendingPlayback = nil
            playing = pendingPlayback
        }
    }

    private func loadDetails() async {
        if group.primary.isSeries {
            var all: [MediaItem] = []
            for variant in group.variants {
                guard let server = store.server(for: variant), let token = TokenVault.read(server.id) else { continue }
                all += (try? await store.api.episodes(server, token: token, seriesId: variant.id)) ?? []
            }
            episodes = all
            selectedSeason = Array(Set(all.compactMap(\.parentIndexNumber))).sorted().first
        } else {
            for variant in group.variants {
                guard let server = store.server(for: variant), let token = TokenVault.read(server.id) else { continue }
                playbackInfo[variant] = try? await store.api.playback(server, token: token, item: variant)
            }
        }
    }
}

import SwiftUI
import Combine

@main struct GuoPlayerApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.15, green: 0.84, blue: 0.91))
        }
    }
}

@MainActor final class AppChrome: ObservableObject {
    @Published var selectedTab = 0
    @Published var showingSettings = false
    @Published var hidesNavigation = false
    @Published var libraryCategory: String? = nil
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chrome = AppChrome()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.035, green: 0.065, blue: 0.10).ignoresSafeArea()
                Group {
                    switch chrome.selectedTab {
                    case 1: NavigationStack { LibraryView() }
                    case 2: NavigationStack { SearchView() }
                    default: NavigationStack {
                        if store.hasTMDBCredential && (store.tmdbLoading || !store.tmdbLists.isEmpty) { TMDBDiscoverHome() }
                        else { ImmersiveDiscoverView() }
                    }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !chrome.hidesNavigation {
                    FloatingNavigationBar()
                        .background(Color(red: 0.035, green: 0.065, blue: 0.10).ignoresSafeArea(edges: .bottom))
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
                if horizontal < -80 && value.startLocation.x > geometry.size.width - 32 {
                    chrome.selectedTab = min(2, chrome.selectedTab + 1)
                } else if horizontal > 80 && value.startLocation.x < 32 {
                    chrome.selectedTab = max(0, chrome.selectedTab - 1)
                }
            })
        }
        .environmentObject(chrome)
        .sheet(isPresented: $chrome.showingSettings) {
            NavigationStack {
                ServerSettingsView().toolbar { Button("完成") { chrome.showingSettings = false } }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
        }
        .task { await store.refresh(); await store.refreshTMDB() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh(); await store.refreshTMDB() } }
        }
    }
}

struct PosterView: View {
    @EnvironmentObject var store: AppStore
    let item: MediaItem
    var width: CGFloat = 132
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: store.poster(item)) { image in image.resizable().scaledToFill() } placeholder: {
                ZStack { Color.white.opacity(0.08); Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.cyan.opacity(0.65)) }
            }
            .frame(width: width, height: width * 1.47).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1).frame(width: width, alignment: .leading)
            Text(item.year.map { String($0) } ?? item.type).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct MediaRail: View {
    let title: String
    let groups: [MediaGroup]
    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2.bold()).padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(groups) { group in
                            NavigationLink { ImmersiveDetailView(group: group) } label: { PosterView(item: group.primary) }
                                .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
            }
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let featured = store.groups.first(where: { !$0.primary.backdropImageTags.isEmpty }) ?? store.groups.first {
                    NavigationLink { DetailView(group: featured) } label: {
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: store.poster(featured.primary, backdrop: true)) { image in image.resizable().scaledToFill() } placeholder: { Color(red: 0.06, green: 0.20, blue: 0.25) }
                                .frame(height: 360).frame(maxWidth: .infinity).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GUOPLAYER · 为你发现").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.cyan)
                                Text(featured.title).font(.largeTitle.bold()).lineLimit(2)
                                Text("\(featured.primary.year.map { String($0) } ?? "")  ·  \(featured.variants.count) 个片源").font(.subheadline)
                                Label("查看详情", systemImage: "play.fill").font(.headline).padding(.top, 6)
                            }.padding(24)
                        }.frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
                    }.buttonStyle(.plain)
                } else if store.servers.isEmpty {
                    VStack(spacing: 16) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 112, height: 112)
                        Text("欢迎使用 GuoPlayer").font(.title.bold())
                        Text("请先在设置中添加你自己的 Emby 服务器。")
                    }.multilineTextAlignment(.center).padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 320)
                } else if store.isLoading {
                    ProgressView("正在读取媒体库").frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ContentUnavailableView("暂无媒体", systemImage: "film", description: Text("请检查服务器媒体库权限，然后下拉刷新。"))
                }
                MediaRail(title: "继续观看", groups: store.resumeGroups)
                MediaRail(title: "最近添加", groups: Array(store.groups.prefix(40)))
                MediaRail(title: "电影", groups: store.groups.filter { $0.primary.type == "Movie" })
                MediaRail(title: "电视剧与动漫", groups: store.groups.filter { $0.primary.type == "Series" })
            }.padding(.bottom, 40)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.10))
        .navigationTitle("发现")
        .toolbar { Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") } }
        .refreshable { await store.refresh() }
        .overlay(alignment: .bottom) { if let error = store.error { Text(error).font(.caption).padding(8).background(.red.opacity(0.8)).clipShape(Capsule()).padding() } }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var chrome: AppChrome
    @State private var showingAdd = false
    @State private var selected: UUID?
    @State private var selectedLibrary: String?
    @State private var libraryItems: [MediaItem] = []
    @State private var libraryOffset = 0
    @State private var canLoadMore = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("资源库").font(.headline)
                    Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加 Emby 媒体库")
                    Spacer()
                }.padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.servers) { server in
                            Button { selected = selected == server.id ? nil : server.id } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image("BrandMark").resizable().scaledToFit().frame(width: 30, height: 30).clipShape(Circle())
                                    Text(server.name).font(.subheadline.bold()).lineLimit(1)
                                    Text("\(store.items.filter { $0.serverId == server.id }.count) 个已读取项目").font(.caption2).foregroundStyle(.secondary)
                                }.frame(width: 185, alignment: .leading).padding(15)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
                                    .overlay { RoundedRectangle(cornerRadius: 17).stroke(selected == server.id ? Color.cyan : Color.clear, lineWidth: 1) }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal)
                }

                Picker("服务器", selection: $selected) {
                    Text("全部服务器").tag(UUID?.none)
                    ForEach(store.servers) { server in Text(server.name).tag(Optional(server.id)) }
                }.pickerStyle(.menu).padding(.horizontal)
                Picker("分类", selection: $chrome.libraryCategory) {
                    Text("全部类型").tag(String?.none)
                    Text("电影").tag(Optional("Movie"))
                    Text("电视剧与动漫").tag(Optional("Series"))
                    Text("收藏").tag(Optional("Favorite"))
                }.pickerStyle(.segmented).padding(.horizontal)
                if let selected, let libraries = store.libraries[selected], !libraries.isEmpty {
                    Picker("媒体库", selection: $selectedLibrary) {
                        Text("全部媒体库").tag(String?.none)
                        ForEach(libraries) { item in Text(item.name).tag(Optional(item.id)) }
                    }.pickerStyle(.menu).padding(.horizontal)
                }
                let libraryKeys = Set(libraryItems.map { "\($0.serverId):\($0.id)" })
                let groups = store.groups.filter { group in group.variants.contains { variant in
                    (selected == nil || variant.serverId == selected) && (selectedLibrary == nil || libraryKeys.contains("\(variant.serverId):\(variant.id)"))
                    && (chrome.libraryCategory == nil || (chrome.libraryCategory == "Favorite" ? group.isFavorite : variant.type == (chrome.libraryCategory ?? "")))
                } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 18) {
                    ForEach(groups) { group in NavigationLink { ImmersiveDetailView(group: group) } label: { PosterView(item: group.primary) }.buttonStyle(.plain) }
                }.padding(.horizontal)
                if canLoadMore { Button("加载更多") { Task { await loadMore() } }.frame(maxWidth: .infinity).padding() }
            }.padding(.bottom, 110).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .navigationTitle("我的媒体")
        .sheet(isPresented: $showingAdd) { AddServerView() }
        .background(Color(red: 0.035, green: 0.065, blue: 0.10))
        .onChange(of: selected) { _, _ in selectedLibrary = nil; libraryItems = []; libraryOffset = 0; canLoadMore = true }
        .task(id: selectedLibrary) {
            canLoadMore = true; libraryOffset = 0; libraryItems = []
            guard let id = selectedLibrary, let serverId = selected, let server = store.servers.first(where: { $0.id == serverId }), let token = TokenVault.read(serverId) else { return }
            if let contents = try? await store.api.items(server, token: token, parentId: id, limit: 300) {
                libraryItems = contents
                libraryOffset = contents.count
                canLoadMore = contents.count == 300
                let known = Set(store.items.map { "\($0.serverId):\($0.id)" })
                store.items += contents.filter { !known.contains("\($0.serverId):\($0.id)") }
            }
        }
    }
    private func loadMore() async {
        if let id = selectedLibrary, let serverId = selected, let server = store.servers.first(where: { $0.id == serverId }), let token = TokenVault.read(serverId) {
            let page = (try? await store.api.items(server, token: token, parentId: id, limit: 300, start: libraryOffset)) ?? []
            libraryOffset += page.count; canLoadMore = page.count == 300
            libraryItems += page
            let known = Set(store.items.map { "\($0.serverId):\($0.id)" })
            store.items += page.filter { !known.contains("\($0.serverId):\($0.id)") }
        } else {
            canLoadMore = await store.loadMore(serverId: selected) > 0
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var term = ""
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 18) {
                ForEach(store.searchGroups) { group in NavigationLink { ImmersiveDetailView(group: group) } label: { PosterView(item: group.primary) }.buttonStyle(.plain) }
            }.padding().padding(.bottom, 110)
        }
        .navigationTitle("搜索")
        .searchable(text: $term, prompt: "搜索所有 Emby 服务器")
        .task(id: term) { try? await Task.sleep(for: .milliseconds(350)); if !Task.isCancelled { await store.search(term) } }
    }
}

struct DetailView: View {
    @EnvironmentObject var store: AppStore
    let group: MediaGroup
    @State private var episodes: [MediaItem] = []
    @State private var selectedSeason: Int? = nil
    @State private var selectedServer: UUID? = nil
    @State private var playing: MediaItem?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: store.poster(group.primary, backdrop: true)) { $0.resizable().scaledToFill() } placeholder: { Color.cyan.opacity(0.1) }
                        .frame(height: 280).frame(maxWidth: .infinity).clipped()
                    LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    Text(group.title).font(.largeTitle.bold()).padding(20)
                }.frame(height: 280)
                HStack { Text(group.primary.year.map { String($0) } ?? ""); if let rating = group.primary.communityRating { Text(String(format: "%.1f ★", rating)) }; Text("\(group.variants.count) 个片源") }.foregroundStyle(.secondary)
                Text(group.primary.overview ?? "暂无简介").font(.body)
                HStack(spacing: 12) {
                    if !group.primary.isSeries { Button { playing = group.primary } label: { Label("播放", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent) }
                    Button { Task { await store.toggleFavorite(group.primary) } } label: { Label(group.isFavorite ? "已收藏" : "收藏", systemImage: group.isFavorite ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                }
                Text("片源").font(.title2.bold())
                ForEach(group.variants) { item in
                    Button { if item.isSeries { selectedServer = item.serverId } else { playing = item } } label: {
                        HStack { Image(systemName: "server.rack"); Text(store.server(for: item)?.name ?? "Emby"); Spacer(); Text(item.isSeries ? "筛选选集" : "播放"); Image(systemName: "chevron.right") }
                            .padding().background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                if group.primary.isSeries {
                    Text("选集").font(.title2.bold())
                    if selectedServer != nil { Button("显示全部服务器选集") { selectedServer = nil }.font(.caption) }
                    let seasons = Array(Set(episodes.compactMap(\.parentIndexNumber))).sorted()
                    if !seasons.isEmpty {
                        Picker("季", selection: $selectedSeason) { ForEach(seasons, id: \.self) { season in Text(season == 0 ? "特别篇" : "第\(season)季").tag(Optional(season)) } }.pickerStyle(.segmented)
                    }
                    ForEach(episodes.filter { (selectedSeason == nil || $0.parentIndexNumber == selectedSeason) && (selectedServer == nil || $0.serverId == selectedServer) }.sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }) { episode in
                        Button { playing = episode } label: {
                            HStack { Text(String(format: "%02d", episode.indexNumber ?? 0)).font(.title3.monospacedDigit()).foregroundStyle(.cyan); VStack(alignment: .leading) { Text(episode.name).lineLimit(2); Text(store.server(for: episode)?.name ?? "").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "play.circle.fill") }
                                .padding().background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.10))
        .toolbar(.hidden, for: .tabBar)
        .task { if group.primary.isSeries { await loadEpisodes() } }
        .fullScreenCover(item: $playing) { item in PlayerView(item: item, playlist: episodes.filter { $0.serverId == item.serverId }.sorted { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }) }
    }
    private func loadEpisodes() async {
        var all: [MediaItem] = []
        for variant in group.variants {
            guard let server = store.server(for: variant), let token = TokenVault.read(server.id) else { continue }
            all += (try? await store.api.episodes(server, token: token, seriesId: variant.id)) ?? []
        }
        episodes = all
        selectedSeason = Array(Set(all.compactMap(\.parentIndexNumber))).sorted().first
    }
}

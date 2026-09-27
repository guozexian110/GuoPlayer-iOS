import SwiftUI

private let homeBackground = Color(red: 0.035, green: 0.065, blue: 0.10)
private let homeAccent = Color(red: 0.15, green: 0.84, blue: 0.91)

struct TMDBDiscoverHome: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var chrome: AppChrome
    private let columns = [GridItem(.adaptive(minimum: 290), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !store.tmdbFeedReady && !store.hasTMDBCredential && !store.tmdbLoading {
                    ContentUnavailableView("自动内容暂不可用", systemImage: "wifi.exclamationmark",
                                           description: Text(store.tmdbError ?? "请检查网络后重试。"))
                    Button("重新加载") { Task { await store.refreshTMDB() } }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                } else {
                    if store.tmdbLoading && store.tmdbLists.isEmpty {
                        ProgressView("正在读取 TMDb").frame(maxWidth: .infinity, minHeight: 240)
                    }
                    if let error = store.tmdbError {
                        Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 18)
                    }
                    if let hero = store.tmdbLists["day"]?.first { heroCard(hero) }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").foregroundStyle(homeAccent)
                        Text("每次打开 App 时更新 · 影视资料来自 TMDb")
                    }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 18)
                    trendRail("今日趋势", key: "day")
                    trendRail("本周趋势", key: "week")
                    featureCards
                    posterRail("正在热映", key: "now")
                    posterRail("今日动漫", key: "anime")
                    tileRail("播出平台", tiles: [("Netflix", "netflix"), ("Disney+", "disney"), ("Apple TV+", "apple")])
                    tileRail("分类浏览", tiles: [("最新电影", "movie"), ("动画", "animation"), ("儿童与家庭", "family"), ("热门剧集", "tv")])
                    tileRail("电影公司", tiles: [("Universal", "universal"), ("Paramount", "paramount"), ("Columbia", "columbia"), ("Marvel", "marvel")])
                    HStack(alignment: .top, spacing: 12) {
                        ranking("高分剧集", key: "topTV")
                        ranking("高分电影", key: "topMovie")
                    }.padding(.horizontal, 16)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 38)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(homeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refreshTMDB(); await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("GuoPlayer").font(.headline.bold())
                Text("发现好内容").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { chrome.selectedTab = 2 } label: { Image(systemName: "magnifyingglass").font(.title3) }
                .accessibilityLabel("搜索 Emby")
            Button { chrome.showingSettings = true } label: { Image(systemName: "gearshape").font(.title3) }
                .accessibilityLabel("设置")
        }.foregroundStyle(.white).padding(.horizontal, 18)
    }

    private func heroCard(_ title: TMDBTitle) -> some View {
        NavigationLink { TMDBTitleDetail(title: title) } label: {
            ZStack(alignment: .bottomLeading) {
                TMDBImage(url: title.backdropURL)
                    .frame(height: 260).frame(maxWidth: .infinity).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("GUOPLAYER · 今日精选").font(.caption.bold()).tracking(2).foregroundStyle(homeAccent)
                    Text(title.displayTitle).font(.system(size: 29, weight: .bold)).lineLimit(2)
                    Text("\(title.year) · \(title.kind == "movie" ? "电影" : "剧集") · TMDb")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }.padding(19)
            }.clipShape(RoundedRectangle(cornerRadius: 19))
        }.buttonStyle(.plain).padding(.horizontal, 16)
    }

    private func trendRail(_ label: String, key: String) -> some View { posterRail(label, key: key) }

    private var featureCards: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            feature("热门电影", key: "movie")
            feature("备受欢迎 · 剧集", key: "tv")
        }.padding(.horizontal, 16)
    }
    private func feature(_ label: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let first = store.tmdbLists[key]?.first {
                NavigationLink { TMDBTitleDetail(title: first) } label: {
                    ZStack(alignment: .bottomLeading) {
                        TMDBImage(url: first.backdropURL).frame(height: 165).clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        Text(label).font(.title2.bold()).padding(14)
                    }.clipShape(RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array((store.tmdbLists[key] ?? []).dropFirst().prefix(6))) { title in
                        NavigationLink { TMDBTitleDetail(title: title) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                TMDBImage(url: title.backdropURL).frame(width: 126, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(title.displayTitle).font(.caption).lineLimit(1).frame(width: 126, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 19))
    }

    private func posterRail(_ label: String, key: String) -> some View {
        Group {
            if let titles = store.tmdbLists[key], !titles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(label).font(.headline).padding(.horizontal, 18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 11) {
                            ForEach(Array(titles.prefix(18))) { title in
                                NavigationLink { TMDBTitleDetail(title: title) } label: { poster(title) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    private func poster(_ title: TMDBTitle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TMDBImage(url: title.imageURL).frame(width: 125, height: 183).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title.displayTitle).font(.caption.weight(.medium)).lineLimit(1).frame(width: 125, alignment: .leading)
            Text(title.year).font(.caption2).foregroundStyle(.secondary)
        }.frame(width: 125, alignment: .leading)
    }

    private func tileRail(_ label: String, tiles: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.headline).padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(tiles.indices, id: \.self) { index in
                        let name = tiles[index].0
                        let key = tiles[index].1
                        NavigationLink { TMDBCollectionView(title: name, titles: store.tmdbLists[key] ?? []) } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let first = store.tmdbLists[key]?.first {
                                    TMDBImage(url: first.backdropURL).frame(width: 190, height: 92).clipped()
                                } else { Color.white.opacity(0.07).frame(width: 190, height: 92) }
                                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                                Text(name).font(.headline.bold()).padding(11)
                            }.frame(width: 190, height: 92).clipShape(RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    private func ranking(_ label: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline).frame(maxWidth: .infinity)
            ForEach(0..<min(3, store.tmdbLists[key]?.count ?? 0), id: \.self) { index in
                let title = store.tmdbLists[key]![index]
                NavigationLink { TMDBTitleDetail(title: title) } label: {
                    HStack(spacing: 7) {
                        Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(homeAccent)
                        Text(title.displayTitle).font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct TMDBImage: View {
    let url: URL?
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } placeholder: {
                Rectangle().fill(Color(red: 0.10, green: 0.26, blue: 0.32))
                    .overlay { Image(systemName: "film").foregroundStyle(.white.opacity(0.45)) }
            }
        }
    }
}

private struct TMDBCollectionView: View {
    let title: String
    let titles: [TMDBTitle]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 18) {
                ForEach(titles) { item in
                    NavigationLink { TMDBTitleDetail(title: item) } label: {
                        VStack(alignment: .leading) {
                            TMDBImage(url: item.imageURL).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(item.displayTitle).font(.caption).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }.navigationTitle(title).background(homeBackground)
    }
}

private struct TMDBTitleDetail: View {
    @EnvironmentObject private var store: AppStore
    let title: TMDBTitle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TMDBImage(url: title.backdropURL).frame(height: 250).clipped()
                Text(title.displayTitle).font(.largeTitle.bold())
                Text("\(title.year) · \(title.kind == "movie" ? "电影" : "剧集") · TMDb")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(title.overview?.isEmpty == false ? title.overview! : "暂无简介")
                if let group = store.embyGroup(for: title) {
                    NavigationLink { ImmersiveDetailView(group: group) } label: {
                        Label("查看 \(group.variants.count) 个 Emby 片源", systemImage: "play.rectangle.fill")
                    }.buttonStyle(.borderedProminent)
                } else {
                    Label("当前 Emby 媒体库没有匹配片源", systemImage: "externaldrive.badge.questionmark")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("影视信息来自 TMDb；播放内容由你添加的 Emby 服务器提供。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.bottom, 40)
        }.background(homeBackground).navigationBarTitleDisplayMode(.inline)
    }
}

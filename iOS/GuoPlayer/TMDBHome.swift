import SwiftUI

private let homeBackground = Color(red: 0.035, green: 0.065, blue: 0.10)
private let homeAccent = Color(red: 0.15, green: 0.84, blue: 0.91)

struct TMDBDiscoverHome: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var chrome: AppChrome
    @AppStorage("homeModuleOrder") private var moduleOrder = HomeLayoutEditor.defaultOrder
    @AppStorage("homeHiddenModules") private var hiddenModules = ""
    @AppStorage("homeHeroSource") private var heroSource = "movie"
    @AppStorage("homeDaySource") private var daySource = "day"
    @AppStorage("homeWeekSource") private var weekSource = "week"
    @AppStorage("homeDayTitle") private var dayTitle = "今日趋势"
    @AppStorage("homeWeekTitle") private var weekTitle = "本周趋势"
    @State private var heroIndex = 0
    @State private var editing = false
    private var modules: [String] { moduleOrder.split(separator: ",").map(String.init).filter { !hiddenModules.split(separator: ",").contains(Substring($0)) } }
    private var heroes: [TMDBTitle] { Array((store.tmdbLists[heroSource] ?? []).prefix(8)) }

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = min(max(geometry.size.width * 1.38, 470), 690)
            ScrollView {
                VStack(spacing: 0) {
                    carousel(height: heroHeight)
                    if let error = store.tmdbError { Text(error).font(.caption).foregroundStyle(.orange).padding(18) }
                    LazyVStack(alignment: .leading, spacing: 25) {
                        ForEach(modules, id: \.self) { module in section(module) }
                        Button { editing = true } label: { Label("编辑首页", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity).padding(14) }
                            .buttonStyle(.bordered).padding(.horizontal, 18)
                        Text("影视资料来自 TMDb · 播放片源来自你的 Emby")
                            .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }.padding(.top, 20).padding(.bottom, 30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
                }
            }.ignoresSafeArea(edges: .top)
                .background {
                    ZStack {
                        homeBackground
                        if let first = heroes.first { TMDBImage(url: first.backdropURL).blur(radius: 80).opacity(0.18) }
                    }.ignoresSafeArea()
                }
                .overlay(alignment: .topTrailing) {
                    Button { editing = true } label: { Image(systemName: "slider.horizontal.3").padding(11).background(.ultraThinMaterial, in: Circle()) }
                        .padding(.trailing, 18).padding(.top, 6).accessibilityLabel("编辑首页")
                }
        }.toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refreshTMDB(); await store.refresh() }
            .sheet(isPresented: $editing) { NavigationStack { HomeLayoutEditor() }.presentationDetents([.large]) }
    }

    private func carousel(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if heroes.isEmpty {
                ProgressView("正在更新影视资料").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $heroIndex) {
                    ForEach(Array(heroes.enumerated()), id: \.element.id) { index, title in
                        NavigationLink { TMDBTitleDetail(title: title) } label: {
                            ZStack(alignment: .bottom) {
                                TMDBImage(url: title.backdropURL).frame(height: height).clipped()
                                LinearGradient(colors: [.clear, .black.opacity(0.08), homeBackground.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                                VStack(spacing: 8) {
                                    Text(title.displayTitle).font(.system(size: 34, weight: .bold)).lineLimit(2)
                                    Text(title.metadata).font(.caption).foregroundStyle(.white.opacity(0.8))
                                    Text(title.overview ?? "").font(.caption).lineLimit(2).foregroundStyle(.white.opacity(0.75))
                                    if let rating = title.voteAverage { Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill").font(.caption.bold()).foregroundStyle(homeAccent) }
                                }.multilineTextAlignment(.center).padding(.horizontal, 28).padding(.bottom, 34)
                            }
                        }.buttonStyle(.plain).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) {
                    ForEach(heroes.indices, id: \.self) { index in
                        Circle().fill(index == heroIndex ? Color.white : Color.white.opacity(0.35)).frame(width: 5, height: 5)
                    }
                }.padding(.bottom, 14)
            }
        }.frame(height: height)
        .onChange(of: heroSource) { _, _ in heroIndex = 0 }
    }

    @ViewBuilder private func section(_ module: String) -> some View {
        switch module {
        case "resume": WideMediaRail(title: "继续观看", groups: store.resumeGroups, showsProgress: true)
        case "day": wideRail(dayTitle, key: daySource)
        case "week": wideRail(weekTitle, key: weekSource)
        case "popular": popularCard
        case "now": posterRail("正在热映", key: "now")
        case "anime": posterRail("今日动漫", key: "anime")
        case "providers": tileRail("播出平台", tiles: [("Netflix", "netflix"), ("Disney+", "disney"), ("Apple TV+", "apple"), ("Max", "max"), ("Hulu", "hulu"), ("Prime Video", "prime"), ("Paramount+", "paramountPlus")])
        case "genres": categoryRail
        case "companies": tileRail("电影公司", tiles: [("Universal", "universal"), ("Paramount", "paramount"), ("Columbia", "columbia"), ("Marvel", "marvel")])
        case "rankings": HStack(alignment: .top, spacing: 12) { ranking("高分剧集", key: "topTV"); ranking("高分电影", key: "topMovie") }.padding(.horizontal, 16)
        default: EmptyView()
        }
    }

    private func heading(_ label: String, key: String) -> some View {
        NavigationLink { TMDBCollectionView(title: label, titles: store.tmdbLists[key] ?? []) } label: {
            HStack { Text(label).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal, 18)
        }.buttonStyle(.plain)
    }
    private func wideRail(_ label: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(label, key: key)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array((store.tmdbLists[key] ?? []).prefix(20))) { title in
                        NavigationLink { TMDBTitleDetail(title: title) } label: { wideTitle(title, width: 230) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }
    private func wideTitle(_ title: TMDBTitle, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TMDBImage(url: title.backdropURL).frame(width: width, height: width * 0.5625).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title.displayTitle).font(.subheadline).lineLimit(1)
            Text(title.metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(width: width, alignment: .leading)
    }
    private var popularCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = store.tmdbLists["movie"]?.first {
                NavigationLink { TMDBCollectionView(title: "热门电影", titles: store.tmdbLists["movie"] ?? []) } label: {
                    ZStack(alignment: .bottomLeading) {
                        TMDBImage(url: title.backdropURL).frame(height: 250).clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        HStack { Image(systemName: "sparkles"); Text("热门电影"); Spacer(); Image(systemName: "chevron.right") }.font(.title2.bold()).padding(20)
                    }.clipShape(RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array((store.tmdbLists["movie"] ?? []).prefix(8))) { title in
                            NavigationLink { TMDBTitleDetail(title: title) } label: { wideTitle(title, width: 160) }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12)
                }.padding(.bottom, 12)
            }
        }.background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
    private func posterRail(_ label: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(label, key: key)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 11) {
                    ForEach(Array((store.tmdbLists[key] ?? []).prefix(20))) { title in
                        NavigationLink { TMDBTitleDetail(title: title) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                TMDBImage(url: title.imageURL).frame(width: 125, height: 183).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(title.displayTitle).font(.caption).lineLimit(1)
                                Text(title.year).font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: 125, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }
    private func tileRail(_ label: String, tiles: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.headline).padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tiles.indices, id: \.self) { index in
                        let name = tiles[index].0; let key = tiles[index].1
                        NavigationLink { TMDBCollectionView(title: name, titles: store.tmdbLists[key] ?? []) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15).fill(.white.opacity(0.06))
                                HStack(spacing: 6) {
                                    Spacer(minLength: 110)
                                    ForEach(Array((store.tmdbLists[key] ?? []).prefix(2))) { title in
                                        TMDBImage(url: title.imageURL).frame(width: 55, height: 100).rotationEffect(.degrees(15))
                                    }
                                }.offset(x: 8)
                                Text(name).font(.system(size: 21, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15)
                            }.frame(width: 245, height: 98).clipShape(RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }
    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类浏览").font(.headline).padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach([( "最新电影", "movie"), ("动画", "animation"), ("儿童与家庭", "family"), ("热门剧集", "tv"), ("西部", "western"), ("悬疑", "mystery"), ("纪录", "documentary"), ("剧情", "drama")], id: \.1) { label, key in
                        NavigationLink { TMDBCollectionView(title: label, titles: store.tmdbLists[key] ?? []) } label: {
                            HStack(spacing: 12) {
                                TMDBImage(url: store.tmdbLists[key]?.first?.imageURL).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(label).font(.subheadline.bold())
                            }.frame(width: 160, alignment: .leading).padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }
    private func ranking(_ label: String, key: String) -> some View {
        NavigationLink { TMDBCollectionView(title: label, titles: store.tmdbLists[key] ?? []) } label: {
            VStack(spacing: 14) {
                Text("❧  \(label)  ❧").font(.subheadline.bold())
                HStack(spacing: 5) {
                    ForEach(Array((store.tmdbLists[key] ?? []).prefix(3))) { title in
                        TMDBImage(url: title.imageURL).frame(height: 68).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((store.tmdbLists[key] ?? []).prefix(3).enumerated()), id: \.element.id) { index, title in
                        Text("\(index + 1)  \(title.displayTitle)").font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .top).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

struct HomeLayoutEditor: View {
    static let defaultOrder = "resume,day,week,popular,now,anime,providers,genres,companies,rankings"
    static let labels = ["resume": "继续观看", "day": "今日趋势", "week": "本周趋势", "popular": "热门电影", "now": "正在热映", "anime": "今日动漫", "providers": "播出平台", "genres": "分类浏览", "companies": "电影公司", "rankings": "高分榜"]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeModuleOrder") private var order = HomeLayoutEditor.defaultOrder
    @AppStorage("homeHiddenModules") private var hidden = ""
    var body: some View {
        List {
            Section("轮播内容") { NavigationLink("配置轮播数据来源") { HomeDataSourceEditor(module: "hero") } }
            Section("长按拖动模块可调整顺序") {
                ForEach(order.split(separator: ",").map(String.init), id: \.self) { key in
                    HStack {
                        Toggle(Self.labels[key] ?? key, isOn: Binding(get: { !hidden.split(separator: ",").contains(Substring(key)) }, set: { visible in
                            var values = Set(hidden.split(separator: ",").map(String.init)); if visible { values.remove(key) } else { values.insert(key) }; hidden = values.sorted().joined(separator: ",")
                        }))
                        if key == "day" || key == "week" { NavigationLink { HomeDataSourceEditor(module: key) } label: { Image(systemName: "slider.horizontal.3") }.labelsHidden() }
                    }
                }.onMove { indices, destination in
                    var values = order.split(separator: ",").map(String.init); values.move(fromOffsets: indices, toOffset: destination); order = values.joined(separator: ",")
                }
            }
            Section { Text("配置 TMDb 时展示影视榜单；未配置时，同一布局展示 Emby 最近添加、高分作品与服务器。无数据的模块会隐藏。 ").font(.caption).foregroundStyle(.secondary) }
            Button("恢复默认布局") { order = Self.defaultOrder; hidden = "" }
        }.navigationTitle("编辑首页").navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

private struct HomeDataSourceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let module: String
    @AppStorage("homeHeroSource") private var heroSource = "movie"
    @AppStorage("homeDaySource") private var daySource = "day"
    @AppStorage("homeWeekSource") private var weekSource = "week"
    @AppStorage("homeDayTitle") private var dayTitle = "今日趋势"
    @AppStorage("homeWeekTitle") private var weekTitle = "本周趋势"
    private var source: Binding<String> { module == "hero" ? $heroSource : module == "day" ? $daySource : $weekSource }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(module == "hero" ? "轮播内容" : module == "day" ? dayTitle : weekTitle).font(.title2.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array((store.tmdbLists[source.wrappedValue] ?? []).prefix(6))) { title in
                            TMDBImage(url: title.backdropURL).frame(width: 250, height: module == "hero" ? 250 : 141).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                if module != "hero" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("编辑标题").font(.headline).foregroundStyle(.secondary)
                        TextField("模块标题", text: module == "day" ? $dayTitle : $weekTitle).padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据源").font(.headline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("GuoPlayer · TMDb", systemImage: "checkmark.seal.fill").foregroundStyle(homeAccent)
                        Picker("影视榜单", selection: source) {
                            Text("今日趋势").tag("day"); Text("本周趋势").tag("week"); Text("热门电影").tag("movie"); Text("热门剧集").tag("tv"); Text("正在热映").tag("now")
                        }.pickerStyle(.menu)
                        Text("使用本机配置的个人 TMDb 凭据获取榜单。每次打开 App 时更新。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(20)
        }.background(homeBackground).navigationTitle("配置数据来源").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("完成") { dismiss() }.font(.headline).frame(maxWidth: .infinity).padding(18).background(.regularMaterial, in: Capsule()).padding(18)
            }
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 25) {
                    Text(title).font(.system(size: 34, weight: .bold)).padding(.top, 16)
                    if titles.isEmpty { ContentUnavailableView("暂无影视资料", systemImage: "film", description: Text("请刷新首页并检查 TMDb 连接。")) }
                    else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(Array(titles.prefix(5))) { item in
                                    NavigationLink { TMDBTitleDetail(title: item) } label: {
                                        VStack(spacing: 8) {
                                            TMDBImage(url: item.backdropURL).frame(width: min(geometry.size.width * 0.83, 600), height: min(geometry.size.width * 0.47, 338)).clipShape(RoundedRectangle(cornerRadius: 15))
                                            Text(item.displayTitle).font(.headline).lineLimit(1)
                                            Text(item.metadata).font(.caption).foregroundStyle(.secondary)
                                        }.frame(width: min(geometry.size.width * 0.83, 600))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 18)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 12)], spacing: 20) {
                            ForEach(titles) { item in
                                NavigationLink { TMDBTitleDetail(title: item) } label: {
                                    VStack(spacing: 5) {
                                        TMDBImage(url: item.imageURL).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 11))
                                        Text(item.displayTitle).font(.caption).lineLimit(1)
                                        Text(item.year).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 18)
                    }
                }.padding(.bottom, 30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.background {
                ZStack { homeBackground; TMDBImage(url: titles.first?.backdropURL).blur(radius: 80).opacity(0.13) }.ignoresSafeArea()
            }
        }.navigationBarTitleDisplayMode(.inline)
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

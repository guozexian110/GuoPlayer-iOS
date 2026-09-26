import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false
    @State private var editing: EmbyServer?
    var body: some View {
        List {
            Section("Emby 服务器") {
                ForEach(store.servers) { server in
                    Button { editing = server } label: { VStack(alignment: .leading, spacing: 4) {
                        Text(server.name).font(.headline)
                        Text(server.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                        Text(server.username).font(.caption).foregroundStyle(.cyan)
                    } }.buttonStyle(.plain)
                }.onDelete { offsets in for index in offsets { store.remove(store.servers[index]) } }
                Button { showingAdd = true } label: { Label("添加 Emby 服务器", systemImage: "plus.circle.fill") }
            }
            Section { Text("账户密码仅用于登录，不会保存。登录令牌保存在本机 Keychain。应用不包含任何媒体源。") }
        }
        .navigationTitle("设置")
        .sheet(isPresented: $showingAdd) { AddServerView() }
        .sheet(item: $editing) { server in EditServerView(server: server) }
    }
}

struct EditServerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let server: EmbyServer
    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    init(server: EmbyServer) {
        self.server = server
        _name = State(initialValue: server.name)
        _address = State(initialValue: server.baseURL.absoluteString)
        _username = State(initialValue: server.username)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("显示名称", text: $name)
                TextField("服务器地址", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("重新登录密码（改地址或账户时必填）", text: $password)
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await save() } } label: { Text(busy ? "正在保存" : "保存") }.disabled(busy)
            }.navigationTitle("编辑服务器").toolbar { Button("取消") { dismiss() } }
        }
    }
    private func save() async {
        busy = true; error = nil
        do { try await store.updateServer(server, name: name, address: address, username: username, password: password); password = ""; dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct AddServerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("显示名称（可选）", text: $name)
                    TextField("https://example.com:8920", text: $address).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                }
                Section("Emby 账户") {
                    TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await submit() } } label: { if busy { ProgressView() } else { Text("连接并登录") } }
                    .disabled(busy || address.isEmpty || username.isEmpty || password.isEmpty)
            }
            .navigationTitle("添加服务器")
            .toolbar { Button("取消") { dismiss() } }
        }
    }
    private func submit() async {
        busy = true; error = nil
        do { try await store.addServer(name: name, address: address, username: username, password: password); password = ""; dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

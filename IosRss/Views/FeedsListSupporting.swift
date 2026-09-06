import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GroupSectionHeader: View {
    @Environment(AppStore.self) private var store
    let title: String
    let feedCount: Int
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    private var titleSize: Double { store.groupTitleFontSize }
    private var metaSize: Double { max(10, titleSize - 2) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: max(9, titleSize - 2), weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: max(12, titleSize - 1), alignment: .center)
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .textCase(nil)
                if isCollapsed {
                    Text("\(feedCount)")
                        .font(.system(size: metaSize, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .monospacedDigit()
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: max(10, titleSize - 3), weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary, in: .capsule)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(isCollapsed ? "已折叠" : "已展开")")
        .accessibilityHint("点按以\(isCollapsed ? "展开" : "折叠")")
    }
}

struct GroupManagerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renameTarget: FeedGroup?
    @State private var renameText = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                        HStack {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(group.name)
                                .font(.system(size: store.groupTitleFontSize, weight: .medium))
                            Spacer()
                            Text("\(store.feeds.filter { $0.groupID == group.id }.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { renameTarget = group; renameText = group.name }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.deleteGroup(group.id) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: { Text("分组") }
                Section {
                    HStack {
                        TextField("新分组名称", text: $newName)
                        Button("添加") {
                            store.addGroup(name: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重命名分组", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    if let g = renameTarget { store.renameGroup(g.id, to: renameText) }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
        }
    }
}

struct FeedRow: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed
    var body: some View {
        HStack(spacing: 12) {
            FeedIcon(feed: feed)
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.system(size: store.feedTitleFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(feed.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary, in: .capsule)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

struct FeedIcon: View {
    let feed: RSSFeed
    var body: some View {
        Group {
            if let urlStr = feed.faviconURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letter
                    }
                }
            } else {
                letter
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private var letter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.2))
            Text(String(feed.title.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct OPMLDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.xml, .plainText, UTType(filenameExtension: "opml") ?? .xml, UTType(filenameExtension: "rss") ?? .xml]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    var onFinish: () -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish() }
    }
}

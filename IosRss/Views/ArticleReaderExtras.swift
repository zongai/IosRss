import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .label
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct AISummaryCard: View {
    let summary: String
    var providerName: String? = nil
    @Binding var expanded: Bool
    var fontSize: Double = 22

    private var points: [String] {
        AppStore.cleanSummaryText(summary)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").font(.system(size: 14, weight: .semibold))
                    Text("AI 摘要").font(.system(size: 15, weight: .semibold))
                    if let providerName, !providerName.isEmpty {
                        Text(providerName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary, in: .capsule)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12)).foregroundStyle(Color.secondary)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Text(point)
                            .font(.system(size: fontSize))
                            .foregroundStyle(Color.primary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

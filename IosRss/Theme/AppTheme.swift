import SwiftUI
import UIKit

// MARK: - Appearance (follow system / force light / force dark)

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// nil = 交给系统
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Color Theme (reading-friendly palettes)

enum AppColorTheme: String, CaseIterable, Codable, Identifiable {
    case azure
    case sepia
    case midnight
    case forest
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .azure: return "Azure 蓝"
        case .sepia: return "Sepia 纸感"
        case .midnight: return "Midnight 夜读"
        case .forest: return "Forest 松绿"
        case .graphite: return "Graphite 石墨"
        }
    }

    var subtitle: String {
        switch self {
        case .azure: return "主色 #3866D6，清爽默认"
        case .sepia: return "暖纸色，长时间阅读更护眼"
        case .midnight: return "深色低蓝光，夜间阅读"
        case .forest: return "柔和绿调，减少刺眼感"
        case .graphite: return "中性灰，专注正文"
        }
    }

    var isDark: Bool {
        switch self {
        case .midnight, .graphite: return true
        default: return false
        }
    }

    /// 系统深色时优先使用的夜读主题
    static var preferredDark: AppColorTheme { .midnight }
    /// 系统浅色时优先使用的日间主题
    static var preferredLight: AppColorTheme { .azure }

    /// 按当前界面色相解析实际色板（跟随系统时在浅/深色间自动切换）
    static func resolved(selected: AppColorTheme, appearance: AppearanceMode, systemScheme: ColorScheme) -> AppColorTheme {
        let effective: ColorScheme
        switch appearance {
        case .system: effective = systemScheme
        case .light: effective = .light
        case .dark: effective = .dark
        }
        if effective == .dark {
            return selected.isDark ? selected : .preferredDark
        } else {
            return selected.isDark ? .preferredLight : selected
        }
    }

    /// 设置页色板预览用
    var previewColors: [Color] {
        let t = tokens
        return [t.accent, t.background, t.card, t.text]
    }

    var tokens: ThemeTokens {
        switch self {
        case .azure:
            return ThemeTokens(
                text: Color(hex: 0x1A1F36),
                muted: Color(hex: 0x6B7289),
                strong: Color(hex: 0x0F172A),
                accent: Color(hex: 0x3866D6),
                background: Color(hex: 0xF4F7FC),
                card: Color(hex: 0xFFFFFF),
                surface: Color(hex: 0xEEF2FA),
                track: Color(hex: 0xE2E8F4),
                ring: Color(hex: 0x3866D6).opacity(0.12),
                accentSoft: Color(hex: 0x3866D6).opacity(0.12),
                shadow: Color(hex: 0x1A1F36).opacity(0.08)
            )
        case .sepia:
            return ThemeTokens(
                text: Color(hex: 0x3D2B1F),
                muted: Color(hex: 0x8B7355),
                strong: Color(hex: 0x2A1C12),
                accent: Color(hex: 0xA67C52),
                background: Color(hex: 0xF7F0E4),
                card: Color(hex: 0xFFF8EE),
                surface: Color(hex: 0xEFE6D6),
                track: Color(hex: 0xE5D9C5),
                ring: Color(hex: 0xA67C52).opacity(0.14),
                accentSoft: Color(hex: 0xA67C52).opacity(0.12),
                shadow: Color(hex: 0x3D2B1F).opacity(0.07)
            )
        case .midnight:
            return ThemeTokens(
                text: Color(hex: 0xE8ECF6),
                muted: Color(hex: 0x8B93A7),
                strong: Color(hex: 0xFFFFFF),
                accent: Color(hex: 0x5B8DEF),
                background: Color(hex: 0x0E1219),
                card: Color(hex: 0x171C26),
                surface: Color(hex: 0x1E2533),
                track: Color(hex: 0x2A3344),
                ring: Color(hex: 0x5B8DEF).opacity(0.18),
                accentSoft: Color(hex: 0x5B8DEF).opacity(0.16),
                shadow: Color.black.opacity(0.35)
            )
        case .forest:
            return ThemeTokens(
                text: Color(hex: 0x1C2B22),
                muted: Color(hex: 0x5F7366),
                strong: Color(hex: 0x0F1A14),
                accent: Color(hex: 0x3D8B6E),
                background: Color(hex: 0xF2F6F3),
                card: Color(hex: 0xFFFFFF),
                surface: Color(hex: 0xE6EEE9),
                track: Color(hex: 0xD5E0D9),
                ring: Color(hex: 0x3D8B6E).opacity(0.14),
                accentSoft: Color(hex: 0x3D8B6E).opacity(0.12),
                shadow: Color(hex: 0x1C2B22).opacity(0.07)
            )
        case .graphite:
            return ThemeTokens(
                text: Color(hex: 0xE6E8EC),
                muted: Color(hex: 0x9AA0AA),
                strong: Color(hex: 0xFFFFFF),
                accent: Color(hex: 0x7B8CDE),
                background: Color(hex: 0x121418),
                card: Color(hex: 0x1A1D23),
                surface: Color(hex: 0x22262E),
                track: Color(hex: 0x2E333C),
                ring: Color(hex: 0x7B8CDE).opacity(0.16),
                accentSoft: Color(hex: 0x7B8CDE).opacity(0.14),
                shadow: Color.black.opacity(0.40)
            )
        }
    }
}

struct ThemeTokens {
    var text: Color
    var muted: Color
    var strong: Color
    var accent: Color
    var background: Color
    var card: Color
    var surface: Color
    var track: Color
    var ring: Color
    var accentSoft: Color
    var shadow: Color
}

// MARK: - Font family

enum AppFontFamily: String, CaseIterable, Codable, Identifiable {
    case system
    case pingFangSC
    case songti
    case heiti

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统默认"
        case .pingFangSC: return "苹方"
        case .songti: return "宋体"
        case .heiti: return "黑体"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "跟随 iOS 系统字体（SF Pro）"
        case .pingFangSC: return "系统中文字体 PingFang SC"
        case .songti: return "宋体，偏印刷感"
        case .heiti: return "黑体，端庄醒目"
        }
    }
}

// MARK: - Typography (Source Han Sans / system families)

enum AppTypography {
    static func greeting() -> Font { font(size: 26, weight: .semibold) }
    static func title() -> Font { font(size: 22, weight: .semibold) }
    static func section() -> Font { font(size: 19, weight: .semibold) }
    static func body() -> Font { font(size: 14.5, weight: .regular) }
    static func bodyLarge() -> Font { font(size: 16, weight: .regular) }
    static func caption() -> Font { font(size: 12.5, weight: .regular) }
    static func label() -> Font { font(size: 13, weight: .medium) }

    /// 当前选用的字体家族（由设置写入 UserDefaults）
    static var family: AppFontFamily {
        if let raw = UserDefaults.standard.string(forKey: "appFontFamily"),
           let f = AppFontFamily(rawValue: raw) {
            return f
        }
        return .system
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        font(size: size, weight: weight, family: family)
    }

    static func font(size: CGFloat, weight: Font.Weight, family: AppFontFamily) -> Font {
        switch family {
        case .system:
            return .system(size: size, weight: weight)
        case .pingFangSC:
            let name: String
            switch weight {
            case .bold, .heavy, .black, .semibold: name = "PingFangSC-Semibold"
            case .medium: name = "PingFangSC-Medium"
            default: name = "PingFangSC-Regular"
            }
            return UIFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
        case .songti:
            let name = "STSongti-SC-Regular"
            return UIFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight, design: .serif)
        case .heiti:
            let name: String
            switch weight {
            case .bold, .heavy, .black, .semibold: name = "STHeitiSC-Medium"
            default: name = "STHeitiSC-Light"
            }
            return UIFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
        }
    }

    static let titleTracking: CGFloat = -0.8
    static let sectionTracking: CGFloat = 0.6
    static let bodyTracking: CGFloat = 0.3
}

enum AppMetrics {
    static let pageMargin: CGFloat = 26
    static let cardGroupSpacing: CGFloat = 18
    static let innerSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 20
    static let chipRadius: CGFloat = 12
    static let rowRadius: CGFloat = 14
    static let iconButtonSize: CGFloat = 42
}

// MARK: - Environment

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue = AppColorTheme.azure.tokens
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }
}

// MARK: - Shared modifiers

struct SoftCardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = AppMetrics.cardRadius
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.card)
                .shadow(color: theme.shadow, radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(theme.ring, lineWidth: 1)
                )
        )
    }
}

struct SoftIconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var size: CGFloat = AppMetrics.iconButtonSize
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle().fill(theme.surface)
                    .shadow(color: theme.shadow, radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
                    .overlay(Circle().stroke(theme.ring, lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func softCard(radius: CGFloat = AppMetrics.cardRadius) -> some View {
        modifier(SoftCardBackground(radius: radius))
    }

    func appTitleStyle() -> some View {
        font(AppTypography.title()).tracking(AppTypography.titleTracking).lineSpacing(6)
    }

    func appSectionStyle() -> some View {
        font(AppTypography.section()).tracking(AppTypography.sectionTracking)
    }

    func appBodyStyle() -> some View {
        font(AppTypography.body()).tracking(AppTypography.bodyTracking).lineSpacing(3.5)
    }

    func appCaptionStyle() -> some View {
        font(AppTypography.caption()).tracking(0.2)
    }

    /// 列表页统一背景与去默认分隔
    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }
}

private struct AppScreenBackground: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Theme picker row

struct ThemePalettePicker: View {
    @Binding var selection: AppColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AppColorTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            ForEach(0..<theme.previewColors.count, id: \.self) { i in
                                Circle()
                                    .fill(theme.previewColors[i])
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.displayName)
                                .font(AppTypography.label())
                                .foregroundStyle(selection == theme ? Color.primary : Color.primary)
                            Text(theme.subtitle)
                                .font(AppTypography.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.tokens.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppMetrics.rowRadius, style: .continuous)
                            .fill(selection == theme ? theme.tokens.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

import AppKit
import SwiftUI

struct ProtectionProgress: Codable {
    var requiredDays: Int
    var remainingDays: Int
    var periodComplete: Bool
    var qualityReady: Bool
    var ready: Bool
    var message: String
}

struct ScanOutcome: Codable {
    var dryRun: Bool
    var scanned: Int
    var kept: Int
    var rescued: Int
    var quarantined: Int
    var review: Int
    var errors: Int
}

enum GuardianSection: String, CaseIterable, Identifiable {
    case overview, learning, archive, settings, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Przegląd"
        case .learning: return "Nauka i korekty"
        case .archive: return "Odzyskiwanie"
        case .settings: return "Ustawienia"
        case .help: return "Pomoc"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .learning: return "hand.thumbsup"
        case .archive: return "tray.and.arrow.up"
        case .settings: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        }
    }
}

// Service health and permission to move mail are separate facts. In particular,
// a healthy observer must never claim that automatic sorting is active.
struct ProtectionPresentation {
    let title: String
    let detail: String
    let symbol: String
    let tone: Color

    init(_ snapshot: GuardianSnapshot, stale: Bool = false) {
        if stale {
            title = "Nie można potwierdzić stanu"
            detail = "Pokazujemy ostatnio odczytane dane. Sprawdź połączenie z lokalnym silnikiem."
            symbol = "questionmark.shield"
            tone = .orange
        } else if snapshot.health == "critical" || snapshot.health == "attention" {
            title = snapshot.health == "critical" ? "Ochrona wymaga naprawy" : "Ochrona wymaga uwagi"
            detail = snapshot.recommendation
            symbol = snapshot.health == "critical" ? "exclamationmark.shield.fill" : "exclamationmark.triangle.fill"
            tone = snapshot.health == "critical" ? .red : .orange
        } else if !snapshot.configured {
            title = "Połącz swoją pocztę"
            detail = "Przejdź krótką konfigurację, aby rozpocząć bezpieczną próbę."
            symbol = "envelope.badge.shield.half.filled"
            tone = GuardianStyle.accent
        } else if snapshot.automation != "on" {
            title = "Sprawdzanie na Twoje żądanie"
            detail = "Automat jest wyłączony. Guardian sprawdzi pocztę, gdy uruchomisz sprawdzanie."
            symbol = "pause.circle.fill"
            tone = .secondary
        } else if snapshot.mode == "protect" {
            title = "Odebrane pod obserwacją"
            detail = "Guardian sprawdza pocztę co 2 godziny. Nie przenosi automatycznie wiadomości z Odebranych."
            symbol = "eye.fill"
            tone = GuardianStyle.accent
        } else if snapshot.mode == "active" {
            title = "Porządkowanie jest włączone"
            detail = "Guardian przenosi pewny spam do kwarantanny i odzyskuje ważne wiadomości z folderu SPAM."
            symbol = "checkmark.shield.fill"
            tone = GuardianStyle.accent
        } else {
            title = "Sprawdź ustawienia ochrony"
            detail = "Nie rozpoznano trybu działania. Uruchom sprawdzenie i naprawę."
            symbol = "questionmark.shield"
            tone = .orange
        }
    }
}

enum GuardianStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.37, green: 0.82, blue: 0.74, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.39, blue: 0.35, alpha: 1)
    })
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

struct GuardianPage<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(GuardianStyle.accent)
                    Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty { Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                content
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(GuardianStyle.background)
    }
}

struct GuardianCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(GuardianStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)))
    }
}

struct PrivacyNote: View {
    var body: some View {
        Label("Analiza na Twoim Macu. Bez otwierania linków i załączników.", systemImage: "lock.shield")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(GuardianStyle.accent).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanOutcomeView: View {
    let outcome: ScanOutcome
    var body: some View {
        GuardianCard {
            Label(outcome.errors > 0 ? "Sprawdzanie zakończone z uwagami" : (outcome.dryRun ? "Wynik bezpiecznej próby" : "Wynik ostatniego sprawdzenia"),
                  systemImage: outcome.errors > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.headline)
            Text(outcome.dryRun ? "To symulacja bieżącego trybu. Żadna wiadomość nie została przeniesiona, usunięta ani użyta do nauki." : "Wyniki tej operacji, bez doliczania wcześniejszych sprawdzeń.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 16) {
                outcomeNumber(outcome.scanned, "Sprawdzone")
                outcomeNumber(outcome.review, outcome.dryRun ? "Do sprawdzenia · plan" : "Do sprawdzenia")
                outcomeNumber(outcome.quarantined, outcome.dryRun ? "Kwarantanna · plan" : "W kwarantannie")
                outcomeNumber(outcome.rescued, outcome.dryRun ? "Odzyskanie · plan" : "Odzyskane")
            }
            if outcome.errors > 0 {
                Text("Nie udało się wykonać części kontroli (\(outcome.errors)). Sprawdź i napraw ochronę przed kolejną próbą.")
                    .foregroundStyle(.orange).font(.callout)
            }
        }
    }
    private func outcomeNumber(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value, format: .number).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct ProtectionProgressView: View {
    @ObservedObject var model: GuardianModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Droga do automatycznego porządkowania", systemImage: "checklist").font(.headline)
                Spacer()
            }
            if let progress = model.snapshot.protection {
                HStack {
                    Text(progress.periodComplete ? "Okres obserwacji zakończony" : "Pozostało dni obserwacji: \(progress.remainingDays)")
                    Spacer()
                    Text("\(max(0, progress.requiredDays - progress.remainingDays)) / \(progress.requiredDays) dni").foregroundStyle(.secondary)
                }.font(.callout)
                ProgressView(value: Double(max(0, progress.requiredDays - progress.remainingDays)), total: Double(max(1, progress.requiredDays)))
                    .accessibilityLabel("Okres obserwacji")
                Label(progress.qualityReady ? "Jakość decyzji potwierdzona" : "Potrzebne potwierdzenie jakości decyzji", systemImage: progress.qualityReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.callout).foregroundStyle(progress.qualityReady ? GuardianStyle.accent : .secondary)
                Text(progress.message).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Przenoszenie wymaga zakończenia okresu obserwacji i potwierdzenia jakości decyzji. Odśwież stan, aby sprawdzić gotowość.").foregroundStyle(.secondary)
            }
        }
    }
}

struct MainTabs: View {
    @ObservedObject var model: GuardianModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").font(.title).foregroundStyle(GuardianStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mail Guardian").font(.headline)
                        Text("Spokojniej z pocztą").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 24)
                List(GuardianSection.allCases, selection: Binding<GuardianSection?>(get: { model.section }, set: { if let value = $0 { model.section = value } })) { section in
                    Label(section.title, systemImage: section.symbol).padding(.vertical, 6).tag(section)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Działa lokalnie na Macu", systemImage: "lock.shield").font(.caption)
                    Text("O2 Mail Guardian \(model.snapshot.version)").font(.caption2)
                }.foregroundStyle(.secondary).padding(18)
            }.navigationSplitViewColumnWidth(min: 195, ideal: 205, max: 230)
        } detail: {
            switch model.section {
            case .overview: DashboardView(model: model)
            case .learning: LearningView(model: model)
            case .archive: ArchiveView(model: model)
            case .settings: SettingsView(model: model)
            case .help: HelpView(model: model)
            }
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: GuardianModel
    @State private var showDetails = false
    private var presentation: ProtectionPresentation { ProtectionPresentation(model.snapshot, stale: model.snapshotIsStale) }
    var body: some View {
        GuardianPage(eyebrow: "Twoja poczta, pod kontrolą", title: "Przegląd ochrony", subtitle: "Najważniejsze informacje w jednym miejscu.") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: presentation.symbol).font(.system(size: 27)).frame(width: 56, height: 56)
                        .background(presentation.tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(presentation.tone).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(presentation.title).font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text(presentation.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 12) {
                    if model.snapshotIsStale || model.snapshot.health == "critical" || model.snapshot.health == "attention" {
                        Button("Sprawdź i napraw") { Task { await model.repair() } }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Sprawdź pocztę teraz") { Task { await model.runNow() } }.buttonStyle(.borderedProminent)
                    }
                    if model.snapshot.automation != "on" && model.snapshot.firstDryRun {
                        Button("Włącz automat") { Task { await model.setAutomation(true) } }
                    }
                    Spacer()
                }.controlSize(.large).disabled(model.busy)
                Divider()
                if model.snapshot.mode == "protect", let progress = model.snapshot.protection {
                    HStack {
                        Text(progress.ready ? "Możesz już włączyć porządkowanie" : "Obserwacja: \(max(0, progress.requiredDays - progress.remainingDays)) z \(progress.requiredDays) dni")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Zobacz warunki", systemImage: "arrow.right") { model.section = .settings }.buttonStyle(.link)
                    }
                }
                Label(model.snapshot.purgeEnabled ? "Trwałe usuwanie włączone — z kontrolami bezpieczeństwa" : "Trwałe usuwanie wyłączone", systemImage: model.snapshot.purgeEnabled ? "exclamationmark.circle" : "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [presentation.tone.opacity(0.08), GuardianStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(presentation.tone.opacity(0.16)))

            if let scan = model.lastScan { ScanOutcomeView(outcome: scan) }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ostatnie 24 godziny").font(.headline)
                    Spacer()
                    if model.snapshotIsStale { Text("Dane mogą być nieaktualne").font(.caption).foregroundStyle(.orange) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 3), spacing: 12) {
                    metric("Sprawdzone", value: model.snapshot.summary.scanned, symbol: "envelope", detail: "analizy wiadomości")
                    metric("Odzyskane", value: model.snapshot.summary.rescued, symbol: "tray.and.arrow.up", detail: "z folderu SPAM")
                    metric("Zatrzymany spam", value: model.snapshot.summary.quarantined, symbol: "shield.lefthalf.filled", detail: "przeniesienia do kwarantanny")
                }
            }
            if model.snapshot.summary.waitingReview > 0 || model.snapshot.summary.pendingMoves > 0 {
                GuardianCard {
                    Label("Warto sprawdzić", systemImage: "tray.full").font(.headline)
                    if model.snapshot.summary.waitingReview > 0 {
                        Text("Wiadomości do Twojej oceny: \(model.snapshot.summary.waitingReview). Znajdziesz je w poczcie o2, w folderze AI-Do-sprawdzenia.")
                        Button("Jak sprawdzić i poprawić decyzję", systemImage: "arrow.right") { model.section = .learning }
                    }
                    if model.snapshot.summary.pendingMoves > 0 {
                        Text("Guardian weryfikuje przerwane operacje: \(model.snapshot.summary.pendingMoves). Nie uruchamiaj ich ponownie ręcznie; skorzystaj z naprawy.").font(.callout).foregroundStyle(.secondary)
                        Button("Sprawdź i napraw") { Task { await model.repair() } }.disabled(model.busy)
                    }
                }
            }
            if model.snapshot.mode == "protect" {
                GuardianCard {
                    ProtectionProgressView(model: model)
                    HStack {
                        Button(model.snapshot.protection?.ready == true ? "Przejdź do włączenia porządkowania" : "Zobacz ustawienia ochrony") { model.section = .settings }
                        Button("Jak pomóc w nauce") { model.section = .learning }
                    }
                    Text("Podczas obserwacji wiadomości z folderu SPAM mogą trafiać do AI-Do-sprawdzenia. Guardian przetwarza też Twoje korekty.").font(.caption).foregroundStyle(.secondary)
                }
            }
            GuardianCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ostatnie udane sprawdzenie").font(.caption).foregroundStyle(.secondary)
                        Text(friendlyDate(model.snapshot.lastSuccess)).font(.callout.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Harmonogram").font(.caption).foregroundStyle(.secondary)
                        Text(model.snapshot.automation == "on" ? "Co 2 godziny" : "Na żądanie").font(.callout.weight(.medium))
                    }
                }
                DisclosureGroup("Szczegóły działania", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ostatnia próba: \(friendlyDate(model.snapshot.lastAttempt))")
                        Text("Kopie w kwarantannie według ostatnich zapisów: \(model.snapshot.summary.waitingQuarantine)")
                        HStack {
                            Button("Zobacz kopie") { model.section = .archive }
                            Button("Odśwież stan") { Task { await model.refresh() } }.disabled(model.busy)
                        }
                    }.font(.callout).padding(.top, 10)
                }
            }
            PrivacyNote()
        }
    }
    private func metric(_ title: String, value: Int, symbol: String, detail: String) -> some View {
        GuardianCard {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary).frame(minHeight: 32, alignment: .topLeading)
            Text(value, format: .number).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).frame(minHeight: 30, alignment: .topLeading)
        }.accessibilityElement(children: .combine)
    }
}

struct OperationFeedback: View {
    @ObservedObject var model: GuardianModel
    @State private var showErrorDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.failure {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.message).font(.callout.weight(.semibold)).textSelection(.enabled)
                        if let recovery = error.recovery { Text(recovery).font(.callout).foregroundStyle(.secondary) }
                        HStack {
                            if failureQuickAction(for: error.code) == .o2Instructions {
                                Link("Otwórz instrukcję o2", destination: URL(string: "https://pomoc.o2.pl/wpkonto/hasla-do-aplikacji-zewnetrznej")!)
                            } else {
                                Button(model.snapshotIsStale ? "Ponów odczyt stanu" : "Sprawdź i napraw") {
                                    model.failure = nil
                                    Task { if model.snapshotIsStale { await model.refresh() } else { await model.repair() } }
                                }.disabled(model.busy)
                            }
                            Button(showErrorDetails ? "Ukryj szczegóły" : "Szczegóły dla pomocy") { showErrorDetails.toggle() }.buttonStyle(.link)
                        }.font(.caption)
                        if showErrorDetails { Text("Kod: \(error.code)").font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Spacer(minLength: 0)
                    Button { model.failure = nil; showErrorDetails = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Zamknij komunikat").accessibilityLabel("Zamknij komunikat")
                }.padding(16).background(.orange.opacity(0.07))
            }
            if model.busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.operationTitle).font(.callout.weight(.medium))
                        Text("Możesz bezpiecznie anulować i wrócić później.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Anuluj") { model.cancel() }
                }.padding(.horizontal, 20).padding(.vertical, 14)
            } else if let notice = model.notice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(GuardianStyle.accent)
                    Text(notice).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Zamknij powiadomienie").accessibilityLabel("Zamknij powiadomienie")
                }.padding(.horizontal, 20).padding(.vertical, 14)
            }
        }.background(.regularMaterial)
    }
}

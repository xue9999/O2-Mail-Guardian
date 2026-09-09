import AppKit
import SwiftUI

struct LearningView: View {
    @ObservedObject var model: GuardianModel
    var body: some View {
        GuardianPage(eyebrow: "Coraz trafniejsze decyzje", title: "Nauka i korekty", subtitle: "Wystarczy przenieść wiadomość do odpowiedniego folderu w poczcie o2.") {
            GuardianCard {
                Label("Zacznij od wiadomości do sprawdzenia", systemImage: "tray.full").font(.headline)
                Text("Otwórz folder AI-Do-sprawdzenia w poczcie o2. Gdy rozpoznasz wiadomość, przenieś ją do jednego z folderów poniżej. Jeśli nie masz pewności, pozostaw ją do późniejszej oceny.")
                    .foregroundStyle(.secondary)
            }
            correctionCard("To ważna wiadomość", symbol: "hand.thumbsup", folder: "AI-Naucz-wazne", detail: "Użyj, gdy prawidłowa wiadomość trafiła do SPAM-u, kwarantanny lub folderu Do sprawdzenia.", result: "Po udanej nauce Guardian przeniesie ją do Odebranych. Twoja korekta blokuje jej automatyczne usunięcie.", count: model.snapshot.trainedHam)
            correctionCard("To jest spam", symbol: "hand.thumbsdown", folder: "AI-Naucz-spam", detail: "Użyj, gdy niechciana wiadomość pozostała w Odebranych lub czeka na Twoją ocenę.", result: "Po udanej nauce Guardian przeniesie ją do kwarantanny.", count: model.snapshot.trainedSpam)
            GuardianCard {
                Text("Co dalej?").font(.headline)
                Text(model.snapshot.automation == "on" ? "Korekty zostaną przetworzone przy następnym automatycznym sprawdzeniu. Możesz też uruchomić je teraz." : "Automat jest wyłączony. Po przeniesieniu wiadomości uruchom sprawdzanie przyciskiem poniżej.").foregroundStyle(.secondary)
                Button("Sprawdź pocztę i przetwórz korekty") { Task { await model.runNow() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                Text("Sprawdzanie obejmuje także pozostałą pocztę, zgodnie z bieżącym trybem ochrony.").font(.caption).foregroundStyle(.secondary)
            }
            if let scan = model.lastScan { ScanOutcomeView(outcome: scan) }
            PrivacyNote()
        }
    }
    private func correctionCard(_ title: String, symbol: String, folder: String, detail: String, result: String, count: Int) -> some View {
        GuardianCard {
            HStack {
                Label(title, systemImage: symbol).font(.title3.weight(.semibold))
                Spacer()
                Text("Korekty: \(count)").font(.caption).foregroundStyle(.secondary)
            }
            Text(detail).foregroundStyle(.secondary)
            HStack {
                Text(folder).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Kopiuj nazwę", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(folder, forType: .string)
                }.help("Kopiuj nazwę folderu do schowka")
            }.padding(12).background(GuardianStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text(result).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ArchiveView: View {
    @ObservedObject var model: GuardianModel
    @State private var selected: ArchiveItem?
    @State private var previewedID: Int64?
    @State private var preview: ArchivePreview?
    @State private var confirmationItem: ArchiveItem?
    @State private var showingRestoreConfirmation = false
    private var canRestore: Bool {
        ArchiveRestoreGate.canRestore(selectedID: selected?.id, previewedID: previewedID, busy: model.busy)
    }
    var body: some View {
        GuardianPage(eyebrow: "Bezpieczny powrót", title: "Odzyskiwanie wiadomości", subtitle: "Znajdź kopię, sprawdź nadawcę i temat, a potem przywróć wiadomość.") {
            HStack {
                Picker("Pokaż", selection: $model.archiveFilter) {
                    Text("Wszystkie kopie").tag("all")
                    Text("Kwarantanna").tag("quarantined")
                    Text("Do sprawdzenia").tag("review")
                    Text("Przywrócone").tag("restored")
                }.frame(maxWidth: 280).disabled(model.busy)
                Spacer()
                Button("Odśwież", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(model.busy)
            }
            if !model.archiveLoaded {
                GuardianCard {
                    EmptyState(symbol: "tray", title: model.busy ? "Wczytuję kopie…" : "Nie udało się odczytać kopii", detail: model.busy ? "Odczytujemy tylko listę. Treść wiadomości pozostaje zaszyfrowana." : "Spróbuj ponownie. Twoje kopie nie zostały zmienione.")
                    if !model.busy { Button("Spróbuj ponownie") { Task { await reload() } } }
                }
            } else if model.archivePage.items.isEmpty {
                GuardianCard {
                    EmptyState(symbol: "tray", title: model.archiveFilter == "all" ? "Nie ma jeszcze kopii" : "Brak kopii w tej kategorii", detail: model.archiveFilter == "all" ? "Kopie pojawią się tutaj, gdy Guardian zabezpieczy wiadomości. Niczego nie musisz teraz odzyskiwać." : "Wybierz inną kategorię, aby zobaczyć pozostałe kopie.")
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ZAPISANE KOPIE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.horizontal, 10)
                        ForEach(model.archivePage.items) { item in
                            Button {
                                selected = item
                                preview = nil
                                previewedID = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(friendlyDate(item.date)).font(.callout.weight(.semibold))
                                    Text(archiveStatusLabel(item.status).capitalized).font(.caption).foregroundStyle(.secondary)
                                    Text("Kopia \(item.id) · \(archiveVerdictLabel(item.verdict))").font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(selected?.id == item.id ? GuardianStyle.accent.opacity(0.12) : GuardianStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected?.id == item.id ? GuardianStyle.accent.opacity(0.4) : .clear))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                                .accessibilityAddTraits(selected?.id == item.id ? .isSelected : [])
                        }
                    }.frame(width: 220)
                    GuardianCard {
                        if let selected {
                            HStack {
                                Text("Kopia \(selected.id)").font(.headline)
                                Spacer()
                                Label("Lokalna kopia", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                            }
                            if let preview, previewedID == selected.id {
                                header("OD", value: preview.from)
                                header("TEMAT", value: preview.subject)
                                header("DATA WIADOMOŚCI", value: preview.date)
                                Divider()
                                Text("Po przywróceniu znajdziesz wiadomość w folderze AI-Do-sprawdzenia w poczcie o2.").font(.callout).foregroundStyle(.secondary)
                                Button("Przywróć wiadomość", systemImage: "tray.and.arrow.up") {
                                    confirmationItem = selected
                                    showingRestoreConfirmation = true
                                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!canRestore)
                            } else {
                                EmptyState(symbol: "envelope.badge.shield.half.filled", title: "Sprawdź, czy to właściwa wiadomość", detail: "Na Twoje żądanie odczytamy tylko nadawcę, temat i datę z zaszyfrowanej kopii.")
                                Button("Pokaż nadawcę i temat") { Task { await loadPreview(selected) } }.buttonStyle(.borderedProminent).disabled(model.busy)
                            }
                            Text("Bez otwierania treści, linków i załączników.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            EmptyState(symbol: "sidebar.left", title: "Wybierz kopię z listy", detail: "Tutaj zobaczysz bezpieczny podgląd. Przywrócenie będzie wymagać Twojego potwierdzenia.")
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            HStack {
                Button("Poprzednia", systemImage: "chevron.left") { Task { await changePage(max(1, model.archivePage.page - 1)) } }.disabled(model.archivePage.page <= 1 || model.busy)
                Spacer()
                Text("Strona \(model.archivePage.page)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Następna", systemImage: "chevron.right") { Task { await changePage(model.archivePage.page + 1) } }.disabled(!model.archivePage.hasNext || model.busy)
            }
            PrivacyNote()
        }
        .task { await model.loadArchive() }
        .onChange(of: model.busy) { busy in
            if !busy && !model.archiveLoaded && model.failure == nil { Task { await model.loadArchive() } }
        }
        .onChange(of: model.archiveFilter) { _ in Task { await changePage(1) } }
        .onDisappear { preview = nil; previewedID = nil }
        .confirmationDialog("Przywrócić kopię \(confirmationItem?.id ?? 0)?", isPresented: $showingRestoreConfirmation) {
            Button("Przywróć do AI-Do-sprawdzenia") {
                if let item = confirmationItem, item.id == previewedID, item.id == selected?.id {
                    Task {
                        await model.restoreArchive(id: item.id)
                        preview = nil
                        previewedID = nil
                    }
                }
            }
            Button("Anuluj", role: .cancel) { confirmationItem = nil }
        } message: {
            Text("Guardian utworzy kopię w folderze AI-Do-sprawdzenia. Sprawdzisz ją w poczcie o2. Żadna wiadomość nie zostanie wysłana.")
        }
    }
    private func header(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Brak informacji" : value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func reload() async { await changePage(model.archivePage.page) }
    private func changePage(_ page: Int) async {
        selected = nil; preview = nil; previewedID = nil
        await model.loadArchive(page: page)
    }
    private func loadPreview(_ item: ArchiveItem) async {
        preview = nil; previewedID = nil
        let result = await model.previewArchive(id: item.id)
        if model.section == .archive, selected?.id == item.id, let value = result {
            preview = value
            previewedID = item.id
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: GuardianModel
    @State private var activeConfirmation = ""
    @State private var purgeConfirmation = ""
    @State private var showAdvancedSafety = false
    @State private var showActivation = false
    @State private var showObservationConfirmation = false
    var body: some View {
        GuardianPage(eyebrow: "Na Twoich zasadach", title: "Ustawienia ochrony", subtitle: "Zdecyduj, kiedy Guardian sprawdza pocztę i co może z nią robić.") {
            GuardianCard {
                Label("Automatyczne sprawdzanie", systemImage: "clock.arrow.circlepath").font(.headline)
                Toggle("Sprawdzaj pocztę co 2 godziny", isOn: Binding(get: { model.snapshot.automation == "on" }, set: { value in Task { await model.setAutomation(value) } }))
                    .toggleStyle(.switch).disabled(model.busy || !model.snapshot.firstDryRun)
                Text("Zamknięcie okna nie zatrzymuje automatu. Wyłącz tę opcję, jeśli chcesz sprawdzać pocztę tylko na żądanie.").font(.callout).foregroundStyle(.secondary)
            }
            GuardianCard {
                Label("Przenoszenie wiadomości", systemImage: "tray.2").font(.headline)
                if model.snapshot.mode == "active" {
                    Text("Automatyczne porządkowanie włączone").font(.title3.weight(.semibold))
                    Text("Pewny spam trafia do kwarantanny, a ważne wiadomości z folderu SPAM wracają do Odebranych. Przypadki niepewne czekają na Twoją ocenę.").foregroundStyle(.secondary)
                    Button("Wróć do obserwacji") { showObservationConfirmation = true }.disabled(model.busy)
                } else {
                    Text("Odebrane pozostają bez zmian").font(.title3.weight(.semibold))
                    Text("W okresie obserwacji wiadomości z folderu SPAM mogą trafiać do AI-Do-sprawdzenia. Twoje korekty nadal są przetwarzane.").foregroundStyle(.secondary)
                    Divider()
                    ProtectionProgressView(model: model)
                    HStack {
                        Button("Włącz porządkowanie…") { activeConfirmation = ""; showActivation = true }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.snapshotIsStale || model.snapshot.protection?.ready != true)
                        Button("Przejdź do nauki") { model.section = .learning }
                    }
                }
            }
            GuardianCard {
                Label("Aplikacja i konto", systemImage: "person.crop.circle").font(.headline)
                Toggle("Uruchamiaj panel po zalogowaniu do Maca", isOn: Binding(get: { model.snapshot.appAutostart }, set: { value in Task { await model.setAppAutostart(value) } })).toggleStyle(.switch).disabled(model.busy)
                Text("Ta opcja dotyczy okna i ikony w pasku menu. Harmonogram sprawdzania ustawiasz osobno powyżej.").font(.callout).foregroundStyle(.secondary)
                Divider()
                Button("Zmień dane konta lub hasło…") { model.reconfigure = true }.disabled(model.busy)
                Text("Zmiana danych zatrzyma automat i będzie wymagać ponownej bezpiecznej próby. Hasło przechowujemy w pęku kluczy macOS.").font(.callout).foregroundStyle(.secondary)
            }
            GuardianCard {
                DisclosureGroup("Zaawansowane: trwałe usuwanie", isExpanded: $showAdvancedSafety) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.snapshot.purgeEnabled ? "Trwałe usuwanie włączone" : "Trwałe usuwanie wyłączone", systemImage: "trash").font(.headline)
                        Text("To osobne uprawnienie. Zwykłe porządkowanie nie wymaga usuwania wiadomości. Włączenie nadal podlega okresom ochronnym i kontrolom jakości.").foregroundStyle(.secondary)
                        if model.snapshot.purgeEnabled {
                            Button("Wyłącz trwałe usuwanie") { Task { await setPurge("disable", confirmation: "") } }.disabled(model.busy)
                        } else {
                            Text("Aby zezwolić na trwałe usuwanie po kontrolach, wpisz WLACZ.").font(.callout)
                            TextField("Potwierdzenie WLACZ", text: $purgeConfirmation).textFieldStyle(.roundedBorder)
                            Button("Włącz trwałe usuwanie", role: .destructive) { Task { await setPurge("enable", confirmation: purgeConfirmation) } }.disabled(purgeConfirmation != "WLACZ" || model.busy)
                        }
                    }.padding(.top, 14)
                }
            }
            PrivacyNote()
        }
        .confirmationDialog("Wrócić do obserwacji?", isPresented: $showObservationConfirmation) {
            Button("Wróć do obserwacji") { Task { await setMode("protect", confirmation: "") } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Guardian przestanie automatycznie przenosić wiadomości z Odebranych. Rozpocznie nowy okres obserwacji, a trwałe usuwanie zostanie wyłączone.")
        }
        .sheet(isPresented: $showActivation) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Włącz porządkowanie poczty", systemImage: "checkmark.shield").font(.title2.bold())
                Text("Guardian będzie przenosić pewny spam z Odebranych do kwarantanny i ratować ważne wiadomości z folderu SPAM. Trwałe usuwanie pozostanie wyłączone.")
                Text("Aby potwierdzić, wpisz AKTYWNY.").font(.callout)
                TextField("Potwierdzenie AKTYWNY", text: $activeConfirmation).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Anuluj", role: .cancel) { showActivation = false }
                    Spacer()
                    Button("Włącz porządkowanie") {
                        Task { await setMode("active", confirmation: activeConfirmation); showActivation = false }
                    }.buttonStyle(.borderedProminent).disabled(activeConfirmation != "AKTYWNY" || model.busy || model.snapshotIsStale || model.snapshot.protection?.ready != true)
                }
            }.padding(28).frame(width: 480).interactiveDismissDisabled(model.busy)
        }
    }
    private func setMode(_ value: String, confirmation: String) async {
        await model.perform("Zmieniam tryb ochrony…") {
            let _: EmptyPayload = try await Backend.call(["mode"], input: ["value": value, "confirm": confirmation])
            return value == "active" ? "Porządkowanie włączone. Trwałe usuwanie pozostaje wyłączone." : "Włączono nowy okres obserwacji."
        }
        if model.failure == nil { activeConfirmation = "" }
    }
    private func setPurge(_ value: String, confirmation: String) async {
        await model.perform {
            let _: EmptyPayload = try await Backend.call(["purge"], input: ["value": value, "confirm": confirmation])
            return "Zmieniono ustawienie trwałego usuwania."
        }
        if model.failure == nil { purgeConfirmation = "" }
    }
}

struct HelpView: View {
    @ObservedObject var model: GuardianModel
    var body: some View {
        GuardianPage(eyebrow: "Pomoc w codziennych sytuacjach", title: "Pomoc", subtitle: "Zacznij od sytuacji, którą chcesz rozwiązać.") {
            GuardianCard {
                Label("Ważny e-mail zniknął", systemImage: "envelope.badge").font(.headline)
                Text("Sprawdź foldery SPAM, AI-Kwarantanna i AI-Do-sprawdzenia w poczcie o2. Ważną wiadomość przenieś do AI-Naucz-wazne. Jeśli jej nie ma, poszukaj lokalnej kopii.").foregroundStyle(.secondary)
                Button("Przejdź do odzyskiwania", systemImage: "arrow.right") { model.section = .archive }
            }
            GuardianCard {
                Label("Spam nadal jest w Odebranych", systemImage: "hand.thumbsdown").font(.headline)
                Text("W trybie obserwacji to zamierzone: Guardian nie przenosi automatycznie wiadomości z Odebranych. Możesz wskazać spam w folderze nauki.").foregroundStyle(.secondary)
                Button("Pokaż instrukcję korekt", systemImage: "arrow.right") { model.section = .learning }
            }
            GuardianCard {
                Label("Ochrona nie działa zgodnie z oczekiwaniami", systemImage: "wrench.and.screwdriver").font(.headline)
                Text("Naprawa sprawdzi lokalny silnik i konfigurację. Pełna kontrola dodatkowo sprawdzi konto oraz foldery.").foregroundStyle(.secondary)
                HStack {
                    Button("Sprawdź i napraw") { Task { await model.repair() } }.buttonStyle(.borderedProminent)
                    Button("Pełna kontrola") { Task { await model.deepDoctor() } }
                }.disabled(model.busy)
            }
            GuardianCard {
                Label("Raport dla osoby pomagającej", systemImage: "doc.text").font(.headline)
                Text("Bez wiadomości, adresów, tematów, załączników i haseł. Raport zostanie zapisany na Biurku; sam zdecydujesz, komu go przekażesz.").foregroundStyle(.secondary)
                Button("Zapisz raport na Biurku") { Task { await model.exportDiagnostics() } }.disabled(model.busy)
            }
            PrivacyNote()
        }
    }
}

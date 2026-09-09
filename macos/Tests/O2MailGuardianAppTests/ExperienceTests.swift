import Testing
@testable import O2MailGuardianApp

extension ProtocolTests {
    @Test func healthyObserverNeverClaimsActiveSorting() {
        var snapshot = GuardianSnapshot()
        snapshot.configured = true
        snapshot.health = "healthy"
        snapshot.automation = "on"
        snapshot.mode = "protect"
        #expect(ProtectionPresentation(snapshot).title == "Odebrane pod obserwacją")
        snapshot.mode = "active"
        #expect(ProtectionPresentation(snapshot).title == "Porządkowanie jest włączone")
        snapshot.automation = "off"
        #expect(ProtectionPresentation(snapshot).title == "Sprawdzanie na Twoje żądanie")
    }

    @Test func unknownModeAndStaleDataCannotAppearHealthy() {
        var snapshot = GuardianSnapshot()
        snapshot.configured = true
        snapshot.health = "healthy"
        snapshot.automation = "on"
        snapshot.mode = "unexpected"
        #expect(ProtectionPresentation(snapshot).title == "Sprawdź ustawienia ochrony")
        snapshot.mode = "active"
        #expect(ProtectionPresentation(snapshot, stale: true).title == "Nie można potwierdzić stanu")
        snapshot.health = "critical"
        #expect(ProtectionPresentation(snapshot).title == "Ochrona wymaga naprawy")
        snapshot.health = "attention"
        #expect(ProtectionPresentation(snapshot).title == "Ochrona wymaga uwagi")
    }

    @Test func olderSnapshotsDoNotInventActivationReadiness() throws {
        let json = #"{"protocol":1,"ok":true,"data":{"configured":true,"health":"healthy","health_label":"OK","recommendation":"OK","automation":"on","mode":"protect","purge_enabled":false,"summary":{},"trained_spam":200,"trained_ham":200,"required_spam":200,"required_ham":200,"first_dry_run":true,"app_autostart":true,"version":"0.3.0"}}"#
        let snapshot = try ProtocolContract.decodeSnapshot(json).data
        #expect(snapshot?.protection == nil)
    }

    @Test func dryRunReportsTheActualOperationRatherThanDailyTotals() async throws {
        let result: CompletionResult = try await Backend.call(["run", "dry-run"])
        #expect(result.completed)
        #expect(result.summary?.dryRun == true)
        #expect(result.summary?.scanned == 24)
        #expect(result.summary?.review == 6)
        #expect(result.summary?.errors == 0)
    }

    @Test func archiveFilterReachesTheBackend() async throws {
        let result: ArchivePage = try await Backend.call(["archive", "list", "1", "review"])
        #expect(result.items.count == 1)
        #expect(result.items.first?.status == "review")
        #expect(!result.hasNext)
    }

    @MainActor
    @Test func reconfigurationRevokesReadinessAndPreviousScanResult() {
        let model = GuardianModel()
        model.snapshot.protection = ProtectionProgress(requiredDays: 14, remainingDays: 0, periodComplete: true, qualityReady: true, ready: true, message: "ready")
        model.lastScan = ScanOutcome(dryRun: true, scanned: 5, kept: 5, rescued: 0, quarantined: 0, review: 0, errors: 0)
        model.markConfigurationCommitted()
        #expect(model.snapshot.protection == nil)
        #expect(model.lastScan == nil)
        #expect(!model.snapshot.firstDryRun)
    }
}

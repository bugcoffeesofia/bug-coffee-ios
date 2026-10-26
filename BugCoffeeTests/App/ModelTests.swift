import Foundation
import HealthKit
import Testing
@testable import BugCoffee

extension AppStateTests {
    @MainActor @Suite struct SessionTests {
        let defaults: UserDefaults

        init() {
            ScratchDefaults.install()
            defaults = ScratchDefaults.standard()
        }

        @Test func startsSignedOutWithoutASavedUID() {
            let session = Session(defaults: defaults, webSync: Fixtures.webSync())
            #expect(session.account == nil)
            #expect(!session.isSignedIn)
        }

        @Test func emptySavedUIDCountsAsSignedOut() {
            defaults.set("", forKey: SharedKeys.defaultsUID)
            #expect(Session(defaults: defaults, webSync: Fixtures.webSync()).account == nil)
        }

        @Test func restoresTheSavedAccount() {
            defaults.set("uid-9", forKey: SharedKeys.defaultsUID)
            defaults.set("nine@example.com", forKey: SharedKeys.defaultsEmail)
            let webSync = Fixtures.webSync()
            let session = Session(defaults: defaults, webSync: webSync)
            #expect(session.account == Account(uid: "uid-9", email: "nine@example.com", idToken: "", refreshToken: ""))
            #expect(session.isSignedIn)
            // Restoring pushes the UID to the watch and starts the (token-less) web sync.
            #expect(WatchSync.shared.context[SharedKeys.uid] as? String == "uid-9")
            #expect(webSync.status == "no token — manual count only")
        }

        @Test func restoresWithoutEmailOrToken() {
            defaults.set("uid-10", forKey: SharedKeys.defaultsUID)
            let session = Session(defaults: defaults, webSync: Fixtures.webSync())
            #expect(session.account?.email == "")
            #expect(session.account?.refreshToken == "")
        }

        @Test func signingInPersistsTheAccount() {
            let session = Session(defaults: defaults, webSync: Fixtures.webSync())
            session.account = Account(uid: "u1", email: "e@x.com", idToken: "id", refreshToken: "")
            #expect(defaults.string(forKey: SharedKeys.defaultsUID) == "u1")
            #expect(defaults.string(forKey: SharedKeys.defaultsEmail) == "e@x.com")
            #expect(defaults.string(forKey: SharedKeys.defaultsRefresh) == "")
            #expect(WatchSync.shared.context[SharedKeys.email] as? String == "e@x.com")
        }

        @Test func signOutForgetsEverything() {
            let webSync = Fixtures.webSync()
            let session = Session(defaults: defaults, webSync: webSync)
            session.account = Fixtures.account
            session.signOut()
            #expect(session.account == nil)
            #expect(defaults.string(forKey: SharedKeys.defaultsUID) == nil)
            #expect(defaults.string(forKey: SharedKeys.defaultsEmail) == nil)
            #expect(defaults.string(forKey: SharedKeys.defaultsRefresh) == nil)
            #expect(webSync.status == "idle")
            // A fresh launch comes up signed out.
            #expect(Session(defaults: defaults, webSync: Fixtures.webSync()).account == nil)
        }
    }

    @MainActor @Suite struct LoginModelTests {
        let session: Session

        init() {
            ScratchDefaults.install()
            session = Session(defaults: ScratchDefaults.standard(), webSync: Fixtures.webSync())
        }

        @Test func canSubmitNeedsBothFieldsAndNoPendingRequest() {
            let model = LoginModel { _, _ in Fixtures.account }
            #expect(!model.canSubmit)
            model.email = "a@b.c"
            #expect(!model.canSubmit)
            model.password = "secret"
            #expect(model.canSubmit)
            model.isLoading = true
            #expect(!model.canSubmit)
        }

        @Test func successSignsTheSessionInWithATrimmedEmail() async {
            var received: (String, String)?
            let model = LoginModel { email, password in
                received = (email, password)
                return Fixtures.account
            }
            model.email = "  bug@example.com "
            model.password = " pass "
            model.errorText = "stale"
            await model.signIn(into: session)
            #expect(received?.0 == "bug@example.com")
            #expect(received?.1 == " pass ")
            #expect(session.account == Fixtures.account)
            #expect(model.errorText == nil)
            #expect(!model.isLoading)
        }

        @Test func isLoadingWhileTheRequestIsInFlight() async {
            var wasLoading = false
            var model: LoginModel!
            model = LoginModel { _, _ in
                wasLoading = model.isLoading
                return Fixtures.account
            }
            await model.signIn(into: session)
            #expect(wasLoading)
            #expect(!model.isLoading)
        }

        @Test func localizedErrorsShowTheirDescription() async {
            let model = LoginModel { _, _ in throw AuthError.firebase("USER_DISABLED") }
            await model.signIn(into: session)
            #expect(model.errorText == "This account has been disabled.")
            #expect(session.account == nil)
        }

        @Test func otherErrorsShowTheSystemDescription() async {
            let error = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "plain failure"])
            let model = LoginModel { _, _ in throw error }
            await model.signIn(into: session)
            #expect(model.errorText == "plain failure")
        }
    }

    @MainActor @Suite struct CardModelTests {
        init() { ScratchDefaults.install() }

        @Test func stepsAreClampedAndPersisted() {
            let model = CardModel(stamps: 8, webSync: Fixtures.webSync()) { _ in }
            model.increment()
            #expect(model.stamps == 9)
            #expect(StampStore.count == 9)
            #expect(WatchSync.shared.context[SharedKeys.stamps] as? Int == 9)
            model.increment()
            #expect(model.stamps == 9)
            for _ in 0..<12 { model.decrement() }
            #expect(model.stamps == 0)
            #expect(StampStore.count == 0)
        }

        @Test func startsFromTheStoredCount() {
            StampStore.setCount(6)
            #expect(CardModel(webSync: Fixtures.webSync()).stamps == 6)
        }

        @Test func adoptsTheBackendCount() {
            let webSync = Fixtures.webSync()
            let model = CardModel(stamps: 1, webSync: webSync) { _ in }
            webSync.onMessage(["type": "count", "count": 7])
            #expect(model.stamps == 7)
            #expect(StampStore.count == 7)
        }

        @Test func logSuccessReportsTheDrink() async {
            var logged: [CoffeeDrink] = []
            let model = CardModel(stamps: 0, webSync: Fixtures.webSync()) { logged.append($0) }
            await model.log(.cappuccino)
            #expect(logged == [.cappuccino])
            #expect(model.logResult == "Cappuccino logged to Health ☕️")
            #expect(!model.isLogging)
        }

        @Test func logFailureShowsTheError() async {
            let model = CardModel(stamps: 0, webSync: Fixtures.webSync()) { _ in throw HealthLogger.HealthError.denied }
            await model.log(.espresso)
            #expect(model.logResult == HealthLogger.HealthError.denied.errorDescription)
        }

        @Test func ignoresASecondLogWhileOneIsRunning() async {
            var calls = 0
            var model: CardModel!
            model = CardModel(stamps: 0, webSync: Fixtures.webSync()) { _ in
                calls += 1
                #expect(model.isLogging)
                await model.log(.latte) // re-entrant tap: ignored
            }
            await model.log(.filter)
            #expect(calls == 1)
            #expect(model.logResult == "Filter Coffee logged to Health ☕️")
        }
    }

    @MainActor @Suite struct DiaryModelTests {
        init() { ScratchDefaults.install() }

        @Test func loadsTheBeansJournal() {
            let cup = Fixtures.tasting(rating: 4)
            BlendJournal.save(cup, for: "kul")
            let model = DiaryModel(beanID: "kul")
            #expect(model.entry.entries == [cup])
            #expect(model.editing == nil)
        }

        @Test func addCupOpensABlankEditor() {
            let model = DiaryModel(beanID: "kul")
            model.addCup()
            #expect(model.editing?.isEmpty == true)
        }

        @Test func commitSavesAndReports() {
            var changes = 0
            let model = DiaryModel(beanID: "kul") { changes += 1 }
            let cup = Fixtures.tasting(rating: 5, note: "wow")
            model.commit(cup)
            #expect(model.entry.entries == [cup])
            #expect(BlendJournal.entry(for: "kul").entries == [cup])
            #expect(changes == 1)
        }

        @Test func committingABlankCupDeletesIt() {
            var cup = Fixtures.tasting(rating: 3)
            BlendJournal.save(cup, for: "kul")
            let model = DiaryModel(beanID: "kul")
            cup.rating = 0
            model.commit(cup)
            #expect(model.entry.entries.isEmpty)
            #expect(BlendJournal.entry(for: "kul").entries.isEmpty)
        }

        @Test func deleteAtOffsets() {
            let cups = (0..<3).map { Fixtures.tasting(rating: $0 + 1, daysAgo: Double($0)) }
            cups.forEach { BlendJournal.save($0, for: "sjp") }
            var changes = 0
            let model = DiaryModel(beanID: "sjp") { changes += 1 }
            model.delete(at: IndexSet([0, 2]))
            #expect(model.entry.entries == [cups[1]])
            #expect(changes == 1)
        }

        @Test func cupCountMentionsUnratedCups() {
            let model = DiaryModel(beanID: "ban")
            model.commit(Fixtures.tasting(rating: 4))
            #expect(model.cupCount == "1 cup")
            model.commit(Fixtures.tasting(rating: 2, daysAgo: 1))
            #expect(model.cupCount == "2 cups")
            model.commit(Fixtures.tasting(daysAgo: 2, note: "no stars"))
            #expect(model.cupCount == "3 cups · 2 rated")
        }
    }
}

// MARK: - Errors & catalog

@Suite struct AuthErrorTests {
    @Test(arguments: [
        ("EMAIL_NOT_FOUND", "Wrong email or password."),
        ("INVALID_PASSWORD", "Wrong email or password."),
        ("INVALID_LOGIN_CREDENTIALS", "Wrong email or password."),
        ("USER_DISABLED", "This account has been disabled."),
        ("TOO_MANY_ATTEMPTS_TRY_LATER", "Too many attempts. Please try again later."),
        ("SOMETHING_NEW", "SOMETHING_NEW"),
    ])
    func firebaseCodesReadFriendly(code: String, message: String) {
        #expect(AuthError.firebase(code).errorDescription == message)
    }

    @Test func otherCases() {
        #expect(AuthError.badResponse.errorDescription == "Unexpected response from the server.")
        #expect(AuthError.network(TestError(message: "offline")).errorDescription == "offline")
    }
}

@Suite struct CoffeeDrinkTests {
    @Test func catalog() {
        #expect(CoffeeDrink.allCases.map(\.name) == ["Espresso", "Double Espresso", "Cappuccino", "Latte", "Filter Coffee", "Decaf"])
        #expect(CoffeeDrink.allCases.map(\.caffeineMilligrams) == [64, 128, 64, 64, 95, 3])
        #expect(CoffeeDrink.latte.id == "latte")
    }

    @Test func healthErrorsExplainThemselves() {
        #expect(HealthLogger.HealthError.unavailable.errorDescription == "Health data isn't available on this device.")
        #expect(HealthLogger.HealthError.denied.errorDescription?.contains("Settings → Health") == true)
    }
}

// MARK: - Health

private final class FakeHealthStore: CaffeineHealthStore, @unchecked Sendable {
    var isHealthDataAvailable = true
    var status = HKAuthorizationStatus.sharingAuthorized
    var requested: Set<HKSampleType> = []
    var saved: [HKObject] = []
    var saveError: Error?

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        requested = toShare
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { status }

    func save(_ object: HKObject) async throws {
        if let saveError { throw saveError }
        saved.append(object)
    }
}

@Suite struct HealthLoggerTests {
    @Test func savesADietaryCaffeineSample() async throws {
        let store = FakeHealthStore()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        try await HealthLogger.log(.doubleEspresso, at: date, store: store)

        #expect(store.requested == [HKQuantityType(.dietaryCaffeine)])
        let sample = try #require(store.saved.first as? HKQuantitySample)
        #expect(sample.quantityType == HKQuantityType(.dietaryCaffeine))
        #expect(sample.quantity.doubleValue(for: .gramUnit(with: .milli)) == 128)
        #expect(sample.startDate == date)
        #expect(sample.endDate == date)
        #expect(sample.metadata?[HKMetadataKeyFoodType] as? String == "Double Espresso")
    }

    @Test func unavailableHealthThrows() async {
        let store = FakeHealthStore()
        store.isHealthDataAvailable = false
        await #expect(throws: HealthLogger.HealthError.self) { try await HealthLogger.log(.espresso, store: store) }
        #expect(store.saved.isEmpty)
    }

    @Test(arguments: [HKAuthorizationStatus.notDetermined, .sharingDenied])
    func deniedAccessThrows(status: HKAuthorizationStatus) async {
        let store = FakeHealthStore()
        store.status = status
        await #expect(throws: HealthLogger.HealthError.self) { try await HealthLogger.log(.espresso, store: store) }
        #expect(store.saved.isEmpty)
    }

    @Test func saveErrorsPropagate() async {
        let store = FakeHealthStore()
        store.saveError = TestError()
        await #expect(throws: TestError.self) { try await HealthLogger.log(.decaf, store: store) }
    }

    /// The real store, limited to calls that can't prompt: asking for
    /// authorization shows UI, and saving unauthorized raises an exception.
    @Test func systemStoreReportsAvailabilityAndStatus() {
        let store = SystemHealthStore.shared
        #expect(store.isHealthDataAvailable == HKHealthStore.isHealthDataAvailable())
        #expect(store.authorizationStatus(for: HKQuantityType(.dietaryCaffeine)) != .sharingAuthorized)
    }
}

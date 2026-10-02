import PassKit
import SwiftUI
import Testing
import UIKit
@testable import BugWallet

/// Puts every screen on screen in the states it can be in. These catch views
/// that crash or assert while building their bodies; behavior lives in the
/// model tests.
extension AppStateTests {
    @MainActor @Suite struct ViewRenderingTests {
        private let wide = CGSize(width: 1180, height: 820)
        private let tall = CGSize(width: 820, height: 1180)

        init() { ScratchDefaults.install() }

        private func session(signedIn: Bool) -> Session {
            let session = Session(defaults: ScratchDefaults.standard(), webSync: Fixtures.webSync())
            if signedIn { session.account = Fixtures.account }
            return session
        }

        private func seedDiary() {
            BlendJournal.save(Fixtures.tasting(rating: 4, method: .v60, place: .home, grind: "18 clicks", note: "bright"), for: "kul")
            BlendJournal.save(Fixtures.tasting(daysAgo: 1, method: .latte, note: "no stars"), for: "kul")
            BlendJournal.save(Fixtures.tasting(rating: 5, daysAgo: 2), for: "sjp")
        }

        // MARK: Root & login

        @Test func rootSignedOutShowsLogin() async throws {
            try await render(RootView().environmentObject(session(signedIn: false)))
        }

        @Test func rootSignedInShowsTheTabs() async throws {
            try await render(RootView().environmentObject(session(signedIn: true)))
        }

        @Test func loginStates() async throws {
            let session = session(signedIn: false)
            let model = LoginModel { _, _ in throw TestError() }
            try await render(LoginView(model: model).environmentObject(session)) { hosted in
                model.email = "bug@example.com"
                model.password = "pw"
                model.isLoading = true
                await hosted.settle(0.2)
                model.isLoading = false
                await model.signIn(into: session)
                #expect(model.errorText == "boom")
                await hosted.settle(0.2)
            }
        }

        // MARK: Card

        @Test func cardCompact() async throws {
            StampStore.setCount(4)
            let webSync = Fixtures.webSync()
            let model = CardModel(webSync: webSync) { _ in }
            try await render(CardView(account: Fixtures.account, webSync: webSync, model: model)
                .environmentObject(session(signedIn: true))) { hosted in
                await model.log(.latte)
                #expect(model.logResult != nil)
                webSync.onMessage(["type": "count", "count": 9])
                await hosted.settle(0.2)
                #expect(model.stamps == 9)
            }
        }

        @Test(arguments: [false, true])
        func cardRegular(isWide: Bool) async throws {
            let webSync = Fixtures.webSync()
            try await render(CardView(account: Fixtures.account, webSync: webSync, model: CardModel(stamps: 2, webSync: webSync))
                .environment(\.horizontalSizeClass, .regular)
                .environmentObject(session(signedIn: true)),
                size: isWide ? wide : tall, horizontalSizeClass: .regular)
        }

        @Test func cardDefaultInit() async throws {
            try await render(CardView(account: Fixtures.account).environmentObject(session(signedIn: true)))
        }

        // MARK: Products

        @Test func productsListCompact() async throws {
            seedDiary()
            _ = FavoritesStore.toggle("lat")
            _ = FavoritesStore.toggle("kul")
            try await render(ProductsView(selectedBean: .constant(nil)))
        }

        @Test(arguments: [nil, "kul", "esp", "retired-bean"])
        func productsSplitView(selected: String?) async throws {
            seedDiary()
            try await render(ProductsView(selectedBean: .constant(selected)), size: wide, horizontalSizeClass: .regular)
        }

        @Test func beanPageWithDiary() async throws {
            seedDiary()
            let kul = try #require(CoffeeMenu.byID["kul"])
            var favorite = true
            let binding = Binding(get: { favorite }, set: { favorite = $0 })
            try await render(NavigationStack { BeanDetailView(item: kul, isFavorite: binding, accent: BugBrand.accent) })
        }

        @Test func beanPageWithoutDiaryOrNotes() async throws {
            let espresso = try #require(CoffeeMenu.byID["esp"])
            try await render(NavigationStack {
                BeanDetailView(item: espresso, isFavorite: .constant(false), accent: BugBrand.accent)
            })
        }

        @Test func beanPageOpensTheEditorSheet() async throws {
            seedDiary()
            let sjp = try #require(CoffeeMenu.byID["sjp"])
            let diary = DiaryModel(beanID: "sjp", editing: BlendJournal.entry(for: "sjp").entries.first)
            try await render(NavigationStack {
                BeanDetailView(item: sjp, isFavorite: .constant(false), accent: BugBrand.accent, diary: diary)
            }, settle: 1.0) { hosted in
                #expect(hosted.controller.presentedViewController != nil)
                diary.editing = nil
                await hosted.settle(0.6)
            }
        }

        @Test(arguments: [BrewPlace.bugCoffee, .home])
        func tastingEditor(place: BrewPlace) async throws {
            let tasting = Fixtures.tasting(rating: place == .home ? 3 : 0, place: place, grind: "fine")
            try await render(TastingEditor(tasting: tasting, beanName: "Kultura", accent: BugBrand.accent) { _ in })
        }

        @Test func rowsAndStars() async throws {
            let kul = try #require(CoffeeMenu.byID["kul"])
            let rated = BlendEntry(entries: [TastingEntry(rating: 4)])
            try await render(List {
                ProductRow(item: kul, isFavorite: true, diary: rated, accent: BugBrand.accent) {}
                ProductRow(item: kul, isFavorite: false, accent: BugBrand.accent) {}
                TastingRow(tasting: Fixtures.tasting(rating: 2, grind: "18", note: "note"), accent: BugBrand.accent)
                TastingRow(tasting: Fixtures.tasting(), accent: BugBrand.accent)
                StarRow(rating: 5, accent: BugBrand.accent, size: .caption)
            })
        }

        // MARK: Shared views

        @Test(arguments: [
            (BlendFinderView.Caffeine.regular, BlendFinderView.Serving.black, BlendFinderView.Flavor.surprise),
            (.decaf, .milk, .chocolatey),
            (.regular, .milk, .fruity),
        ])
        func blendFinder(caffeine: BlendFinderView.Caffeine, serving: BlendFinderView.Serving, flavor: BlendFinderView.Flavor) async throws {
            seedDiary()
            BlendJournal.set(BlendEntry(entries: [TastingEntry(rating: 5)]), for: "bbe")
            try await render(BlendFinderView(pickLabel: "Pick", caffeine: caffeine, serving: serving, flavor: flavor) { _ in })
        }

        @Test func blendFinderDefaults() async throws {
            try await render(BlendFinderView(pickLabel: "Pick") { _ in })
        }

        @Test(arguments: [0, 5, 9])
        func stampCard(count: Int) async throws {
            try await render(StampCardView(count: count))
        }

        @Test func fittingScrollViewScrollsTallContent() async throws {
            try await render(FittingScrollView { size in
                Color.red.frame(height: size.height * 2)
            }, size: CGSize(width: 320, height: 300))
        }

        // MARK: Wallet UIKit bits

        @Test func addToWalletButtonForwardsTaps() async throws {
            var taps = 0
            try await render(AddToWalletButton { taps += 1 }.frame(width: 250, height: 48)) { hosted in
                let button = try #require(hosted.views(of: PKAddPassButton.self).first)
                button.sendActions(for: .touchUpInside)
                #expect(taps == 1)
            }
        }

        @Test func walletPresenterFindsTheFrontmostController() async throws {
            try await render(Color.clear) { hosted in
                let presented = UIViewController()
                hosted.controller.present(presented, animated: false)
                await hosted.settle(0.3)
                #expect(WalletPresenter.topViewController() === presented)
                presented.dismiss(animated: false)
                await hosted.settle(0.3)
            }
        }
    }
}

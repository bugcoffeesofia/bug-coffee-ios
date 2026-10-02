import Foundation
import SwiftUI
import Testing
@testable import BugWallet

extension AppStateTests {
    @MainActor @Suite struct FavoritesStoreTests {
        init() { ScratchDefaults.install() }

        @Test func startsEmpty() {
            #expect(FavoritesStore.ids.isEmpty)
        }

        @Test func toggleStarsAndUnstars() {
            #expect(FavoritesStore.toggle("lat") == ["lat"])
            #expect(FavoritesStore.toggle("esp") == ["lat", "esp"])
            #expect(FavoritesStore.ids == ["lat", "esp"])
            #expect(FavoritesStore.toggle("lat") == ["esp"])
            // Stored sorted so the App Group plist is stable.
            #expect(SharedKeys.groupDefaults.stringArray(forKey: SharedKeys.defaultsFavorites) == ["esp"])
        }

        @Test func addNeverUnstars() {
            #expect(FavoritesStore.add("kul") == ["kul"])
            #expect(FavoritesStore.add("kul") == ["kul"])
            #expect(FavoritesStore.ids == ["kul"])
        }
    }

    @MainActor @Suite struct StampStoreTests {
        init() { ScratchDefaults.install() }

        @Test func countIsClampedOnWrite() {
            #expect(StampStore.count == 0)
            StampStore.setCount(4)
            #expect(StampStore.count == 4)
            StampStore.setCount(42)
            #expect(StampStore.count == StampStore.maxStamps)
            StampStore.setCount(-3)
            #expect(StampStore.count == 0)
        }

        @Test func countIsClampedOnRead() {
            SharedKeys.groupDefaults.set(99, forKey: SharedKeys.defaultsStamps)
            #expect(StampStore.count == 9)
            SharedKeys.groupDefaults.set(-1, forKey: SharedKeys.defaultsStamps)
            #expect(StampStore.count == 0)
        }
    }

    @MainActor @Suite struct BlendJournalTests {
        init() { ScratchDefaults.install() }

        @Test func emptyJournal() {
            #expect(BlendJournal.all.isEmpty)
            #expect(BlendJournal.entry(for: "kul") == BlendEntry())
        }

        @Test func corruptDataReadsAsEmpty() {
            SharedKeys.groupDefaults.set(Data("nope".utf8), forKey: SharedKeys.defaultsBlendJournal)
            #expect(BlendJournal.all.isEmpty)
        }

        @Test func setStoresPerBean() {
            let entry = BlendEntry(entries: [Fixtures.tasting(rating: 5)])
            BlendJournal.set(entry, for: "kul")
            #expect(BlendJournal.entry(for: "kul") == entry)
            #expect(BlendJournal.entry(for: "sjp") == BlendEntry())
            #expect(BlendJournal.all.keys.sorted() == ["kul"])
        }

        @Test func saveInsertsNewestFirstAndUpdatesInPlace() {
            let old = Fixtures.tasting(rating: 2, daysAgo: 3)
            let new = Fixtures.tasting(rating: 5, daysAgo: 1)
            BlendJournal.save(old, for: "kul")
            BlendJournal.save(new, for: "kul")
            #expect(BlendJournal.entry(for: "kul").entries.map(\.id) == [new.id, old.id])

            var edited = old
            edited.note = "better second time"
            edited.date = Date(timeIntervalSince1970: 1_800_000_000)
            BlendJournal.save(edited, for: "kul")
            let entries = BlendJournal.entry(for: "kul").entries
            #expect(entries.count == 2)
            #expect(entries.first == edited)
        }

        @Test func deleteRemovesOneCup() {
            let keep = Fixtures.tasting(rating: 4)
            let drop = Fixtures.tasting(rating: 1, daysAgo: 1)
            BlendJournal.save(keep, for: "sjp")
            BlendJournal.save(drop, for: "sjp")
            BlendJournal.delete(drop.id, for: "sjp")
            #expect(BlendJournal.entry(for: "sjp").entries == [keep])
            BlendJournal.delete(UUID(), for: "sjp")
            #expect(BlendJournal.entry(for: "sjp").entries == [keep])
        }
    }

    @MainActor @Suite struct BlendMatcherTests {
        init() { ScratchDefaults.install() }

        @Test func decafOnlyMatchesTheDecafBean() {
            let matches = BlendMatcher.matches(wantsDecaf: true, wantsMilk: true, flavor: .surprise)
            #expect(matches.map(\.id) == ["bbe"])
        }

        @Test func fruityAndBlackPutsFruityBlackBeansFirst() {
            let matches = BlendMatcher.matches(wantsDecaf: false, wantsMilk: false, flavor: .fruity)
            #expect(matches.count == 3)
            // bmb and mkw score 3 (fruity + black), sir scores 2.
            #expect(Set(matches.prefix(2).map(\.id)) == ["bmb", "mkw"])
            #expect(matches.last?.id == "sir")
        }

        @Test func chocolateyWithMilkPrefersChocolateyMilkBeans() {
            let matches = BlendMatcher.matches(wantsDecaf: false, wantsMilk: true, flavor: .chocolatey, limit: 10)
            #expect(matches.count == 7)
            let top = Set(matches.prefix(4).map(\.id))
            #expect(top == ["sjp", "kal", "ban", "kul"])
        }

        @Test func journalRatingsTipTheScale() {
            BlendJournal.set(BlendEntry(entries: [TastingEntry(rating: 5)]), for: "sir")
            let matches = BlendMatcher.matches(wantsDecaf: false, wantsMilk: false, flavor: .chocolatey, limit: 1)
            #expect(matches.map(\.id) == ["sir"])
        }

        @Test func flavorAnswersMapOntoTheMatcher() {
            #expect(BlendFinderView.Flavor.chocolatey.matcher == .chocolatey)
            #expect(BlendFinderView.Flavor.fruity.matcher == .fruity)
            #expect(BlendFinderView.Flavor.surprise.matcher == .surprise)
            #expect(BlendFinderView.Caffeine.allCases.map(\.id) == ["Regular", "Decaf"])
            #expect(BlendFinderView.Serving.allCases.map(\.id) == ["Black", "With milk"])
        }
    }
}

@Suite struct SlotJitterTests {
    @Test func placementIsDeterministicAndBounded() {
        for slot in 0..<9 {
            let a = SlotJitter(slot: slot), b = SlotJitter(slot: slot)
            #expect(a.rotation == b.rotation)
            #expect(a.offset(for: 40) == b.offset(for: 40))
            #expect(abs(a.rotation.degrees) <= 20)
            let offset = a.offset(for: 40)
            #expect(abs(offset.width) <= 40 * 0.12)
            #expect(abs(offset.height) <= 40 * 0.12)
        }
        #expect(SlotJitter(slot: 0).rotation != SlotJitter(slot: 1).rotation)
    }

    @Test func offsetScalesWithTheSlot() {
        let jitter = SlotJitter(slot: 3)
        #expect(abs(jitter.offset(for: 80).width - 2 * jitter.offset(for: 40).width) < 0.0001)
    }
}

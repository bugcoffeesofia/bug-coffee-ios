import Foundation
import Testing
@testable import BugCoffee

@Suite struct BlendInfoTests {
    @Test func everyBeanHasTastingNotes() {
        for bean in CoffeeMenu.beans {
            let info = BlendInfo.byID[bean.id]
            #expect(info != nil, "missing BlendInfo for \(bean.id)")
            #expect(info?.tastingNotes.isEmpty == false)
        }
        #expect(BlendInfo.byID.count == CoffeeMenu.beans.count)
    }

    @Test func onlyTheDecafBeanIsDecaf() {
        #expect(BlendInfo.byID.filter { $0.value.decaf }.map(\.key) == ["bbe"])
    }
}

@Suite struct BrewMethodTests {
    @Test func namesAndEmojiAreFilledIn() {
        for method in BrewMethod.allCases {
            #expect(!method.name.isEmpty)
            #expect(!method.emoji.isEmpty)
            #expect(method.id == method.rawValue)
        }
        #expect(Set(BrewMethod.allCases.map(\.name)).count == BrewMethod.allCases.count)
    }

    @Test func pickerSectionsSplitTheMethods() {
        #expect(BrewMethod.espressoBar.allSatisfy { $0.isEspressoBased })
        #expect(BrewMethod.brewed.allSatisfy { !$0.isEspressoBased })
        #expect(BrewMethod.espressoBar.count + BrewMethod.brewed.count == BrewMethod.allCases.count)
        #expect(BrewMethod.espressoBar.first == .espresso)
        #expect(BrewMethod.brewed.first == .v60)
    }

    @Test(arguments: [
        (BrewMethod.espresso, "☕️"), (.latte, "🥛"), (.coldBrew, "🍹"), (.chemex, "🫖"),
        (.aeropress, "⏳"), (.turkish, "🔥"), (.other, "☕️"),
    ])
    func emojiGroups(method: BrewMethod, emoji: String) {
        #expect(method.emoji == emoji)
    }

    @Test func specificNames() {
        #expect(BrewMethod.v60.name == "V60 / pour-over")
        #expect(BrewMethod.cuban.name == "Cuban (cafecito)")
        #expect(BrewMethod.drip.name == "Filter / drip")
    }
}

@Suite struct BrewPlaceTests {
    @Test func namesAndEmoji() {
        #expect(BrewPlace.allCases.map(\.name) == ["Bug Coffee", "Another café", "Home", "Work", "Elsewhere"])
        #expect(BrewPlace.allCases.map(\.emoji) == ["🐞", "🏠", "🏡", "💼", "📍"])
        #expect(BrewPlace.home.id == "home")
    }

    @Test func grindingYourOwnBeans() {
        #expect(BrewPlace.allCases.filter { $0.grindsOwnBeans } == [.home, .work])
    }
}

@Suite struct TastingEntryTests {
    @Test func emptyUntilItCarriesSomething() {
        #expect(TastingEntry().isEmpty)
        #expect(!TastingEntry(rating: 3).isEmpty)
        #expect(!TastingEntry(grind: "18 clicks").isEmpty)
        #expect(!TastingEntry(note: "syrupy").isEmpty)
        // Method, place and date alone aren't worth keeping.
        #expect(TastingEntry(method: .v60, place: .home).isEmpty)
    }

    @Test func tappingAStarSetsOrClearsTheRating() {
        var entry = TastingEntry()
        entry.tapStar(4)
        #expect(entry.rating == 4)
        entry.tapStar(2)
        #expect(entry.rating == 2)
        entry.tapStar(2)
        #expect(entry.rating == 0)
    }
}

@Suite struct BlendEntryTests {
    @Test func emptyDiary() {
        let entry = BlendEntry()
        #expect(entry.ratedCount == 0)
        #expect(entry.averageRating == 0)
        #expect(entry.rating == 0)
        #expect(entry.averageText == "")
        #expect(entry.latestNote == "")
    }

    @Test func averagesOnlyRatedCups() {
        let entry = BlendEntry(entries: [
            TastingEntry(rating: 4), TastingEntry(rating: 0, note: "no stars"),
            TastingEntry(rating: 3), TastingEntry(rating: 4),
        ])
        #expect(entry.ratedCount == 3)
        #expect(abs(entry.averageRating - 11.0 / 3.0) < 0.0001)
        #expect(entry.rating == 4)
        #expect(entry.averageText == "3.7")
    }

    @Test func roundsHalfUp() {
        #expect(BlendEntry(entries: [TastingEntry(rating: 2), TastingEntry(rating: 3)]).rating == 3)
    }

    @Test func latestNoteSkipsCupsWithoutOne() {
        let entry = BlendEntry(entries: [
            TastingEntry(rating: 5), TastingEntry(note: "newest note"), TastingEntry(note: "older"),
        ])
        #expect(entry.latestNote == "newest note")
    }

    @Test func codableRoundTrip() throws {
        let entry = BlendEntry(entries: [
            Fixtures.tasting(rating: 5, method: .v60, place: .home, grind: "18", note: "bright"),
            Fixtures.tasting(daysAgo: 2, note: "second"),
        ])
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(BlendEntry.self, from: data) == entry)
        // Only the diary is written — never the legacy flat fields.
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["entries"])
    }

    @Test func decodesTheLegacyFlatRecordIntoOneCup() throws {
        let entry = try JSONDecoder().decode(BlendEntry.self, from: Data(#"{"rating": 4, "note": "old note"}"#.utf8))
        #expect(entry.entries.count == 1)
        #expect(entry.entries.first?.rating == 4)
        #expect(entry.entries.first?.note == "old note")
    }

    @Test(arguments: [#"{}"#, #"{"rating": 0, "note": ""}"#])
    func legacyRecordWithNothingInItDecodesEmpty(_ legacy: String) throws {
        #expect(try JSONDecoder().decode(BlendEntry.self, from: Data(legacy.utf8)).entries.isEmpty)
    }
}

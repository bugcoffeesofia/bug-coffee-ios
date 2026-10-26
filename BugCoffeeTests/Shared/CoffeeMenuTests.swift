import Foundation
import Testing
@testable import BugCoffee

@Suite struct CoffeeMenuTests {
    @Test func idsAreUniqueAcrossDrinksAndBeans() {
        let ids = CoffeeMenu.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CoffeeMenu.all.count == CoffeeMenu.drinks.count + CoffeeMenu.beans.count)
        #expect(CoffeeMenu.byID.count == CoffeeMenu.all.count)
    }

    @Test func sectionsHoldTheirCategory() {
        #expect(CoffeeMenu.drinks.allSatisfy { $0.category == .drink })
        #expect(CoffeeMenu.beans.allSatisfy { $0.category == .beans })
    }

    @Test func isCoffeeMeansDecafableDrink() throws {
        #expect(try #require(CoffeeMenu.byID["cap"]).isCoffee)
        #expect(try #require(CoffeeMenu.byID["tea"]).isCoffee == false)
        // Beans aren't a drink, even though coffee is all they are.
        #expect(try #require(CoffeeMenu.byID["kul"]).isCoffee == false)
    }

    @Test func milksAreIndexedByID() {
        #expect(CoffeeMenu.milkByID["oat"]?.name == "Oat")
        #expect(CoffeeMenu.milkByID.count == CoffeeMenu.milks.count)
        #expect(CoffeeMenu.milkSurchargeCents == 60)
        #expect(CoffeeMenu.decafSurchargeCents == 0)
    }

    @Test func favoritesFloatToTheTopInMenuOrder() {
        let drinks = CoffeeMenu.drinks
        let sorted = CoffeeMenu.favoritesFirst(drinks, favorites: ["lat", "esp"])
        #expect(sorted.prefix(2).map(\.id) == ["esp", "lat"])
        #expect(sorted.count == drinks.count)
        #expect(Array(sorted.dropFirst(2)) == drinks.filter { !["esp", "lat"].contains($0.id) })
    }

    @Test func favoritesFirstWithoutFavoritesKeepsOrder() {
        #expect(CoffeeMenu.favoritesFirst(CoffeeMenu.beans, favorites: []) == CoffeeMenu.beans)
    }
}

@Suite struct PriceTests {
    @Test(arguments: [(190, "1.90 €"), (0, "0.00 €"), (1530, "15.30 €")])
    func euro(cents: Int, expected: String) {
        #expect(Price.euro(cents) == expected)
    }

    @Test func dualReproducesTheBoard() {
        // The board prints 3.30 € / 6.45 лв. for a latte.
        #expect(Price.dual(330) == "3.30 € / 6.45 лв.")
        #expect(Price.dual(60) == "0.60 € / 1.17 лв.")
    }
}

@Suite struct BeanLinkTests {
    @Test func beansGetALink() throws {
        let kul = try #require(CoffeeMenu.byID["kul"])
        #expect(BeanLink.url(for: kul)?.absoluteString == "bugcoffee://bean/kul")
    }

    @Test func drinksHaveNoPage() throws {
        #expect(BeanLink.url(for: try #require(CoffeeMenu.byID["esp"])) == nil)
    }

    @Test func linkRoundTrips() throws {
        for bean in CoffeeMenu.beans {
            let url = try #require(BeanLink.url(for: bean))
            #expect(BeanLink.bean(from: url) == bean)
        }
    }

    @Test func schemeAndHostAreCaseInsensitive() throws {
        #expect(BeanLink.bean(from: try #require(URL(string: "BugCoffee://BEAN/sjp")))?.id == "sjp")
    }

    @Test(arguments: [
        "https://bean/kul",          // wrong scheme
        "bugcoffee://drink/kul",     // wrong host
        "bugcoffee://bean/",         // no id
        "bugcoffee://bean/kul/more", // too deep
        "bugcoffee://bean/nope",     // retired / unknown bean
        "bugcoffee://bean/esp",      // a drink, not a bean
    ])
    func rejectsLinksThatArentABean(_ link: String) throws {
        #expect(BeanLink.bean(from: try #require(URL(string: link))) == nil)
    }
}

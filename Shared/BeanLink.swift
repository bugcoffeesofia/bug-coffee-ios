import Foundation

/// Deep links into a single bean's page: `bugcoffee://bean/<id>`, where `<id>`
/// is the bean's `MenuItem.id` ("kul", "sjp"…). Pure Foundation so the app, the
/// iMessage extension and anything else that wants to hand out a link agree on
/// one format.
///
/// The scheme is registered in `BugCoffee/Resources/Info.plist`
/// (CFBundleURLTypes); `RootView` turns an incoming URL into a bean page.
enum BeanLink {
    static let scheme = "bugcoffee"
    /// `bugcoffee://bean/...` — the URL's host, not a path component.
    static let host = "bean"

    /// The link for a bean, or nil for anything that isn't one (drinks have no
    /// page to open).
    static func url(for item: MenuItem) -> URL? {
        guard item.category == .beans else { return nil }
        return url(beanID: item.id)
    }

    static func url(beanID: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(beanID)"
        return components.url
    }

    /// The bean a link points at, or nil when the URL isn't ours or names an id
    /// the menu doesn't carry (an old link after a bean was retired).
    static func bean(from url: URL) -> MenuItem? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host
        else { return nil }
        // "/kul" → "kul". Anything deeper than one component isn't a bean link.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1,
              let item = CoffeeMenu.byID[parts[0]],
              item.category == .beans
        else { return nil }
        return item
    }
}

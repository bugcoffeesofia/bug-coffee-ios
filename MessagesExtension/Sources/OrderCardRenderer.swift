import UIKit

/// Draws the picture shown inside the message bubble, so the chat can see the
/// order at a glance without opening the extension.
enum OrderCardRenderer {
    static func render(_ order: GroupOrder) -> UIImage {
        let size = CGSize(width: 300, height: 175)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true

        let dark = UIColor(red: 31/255, green: 4/255, blue: 9/255, alpha: 1)
        let accent = UIColor(red: 204/255, green: 30/255, blue: 65/255, alpha: 1)

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            dark.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            func draw(_ text: String, at y: CGFloat, font: UIFont, color: UIColor) {
                (text as NSString).draw(
                    at: CGPoint(x: 16, y: y),
                    withAttributes: [.font: font, .foregroundColor: color])
            }

            draw("☕️ Bug Coffee", at: 14, font: .boldSystemFont(ofSize: 18), color: accent)
            draw("Group order", at: 38, font: .systemFont(ofSize: 12),
                 color: .white.withAlphaComponent(0.7))

            var y: CGFloat = 62
            let items = order.aggregated
            for (title, qty) in items.prefix(5) {
                draw("\(qty)× \(title)", at: y, font: .systemFont(ofSize: 13, weight: .medium),
                     color: .white)
                y += 18
            }
            if items.count > 5 {
                draw("+ \(items.count - 5) more…", at: y, font: .systemFont(ofSize: 12),
                     color: .white.withAlphaComponent(0.6))
            }

            draw(order.oneLineSummary, at: size.height - 40,
                 font: .systemFont(ofSize: 11), color: .white.withAlphaComponent(0.5))
            draw(Price.dual(order.totalCents), at: size.height - 24,
                 font: .boldSystemFont(ofSize: 12), color: .white)
        }
    }
}

import Foundation
import HealthKit

/// A coffee the user can log, with a typical caffeine content.
enum CoffeeDrink: String, CaseIterable, Identifiable {
    case espresso
    case doubleEspresso
    case cappuccino
    case latte
    case filter
    case decaf

    var id: String { rawValue }

    var name: String {
        switch self {
        case .espresso:       return "Espresso"
        case .doubleEspresso: return "Double Espresso"
        case .cappuccino:     return "Cappuccino"
        case .latte:          return "Latte"
        case .filter:         return "Filter Coffee"
        case .decaf:          return "Decaf"
        }
    }

    /// Typical caffeine per serving, in milligrams.
    var caffeineMilligrams: Double {
        switch self {
        case .espresso:       return 64
        case .doubleEspresso: return 128
        case .cappuccino:     return 64
        case .latte:          return 64
        case .filter:         return 95
        case .decaf:          return 3
        }
    }
}

/// Writes logged coffees to Apple Health as dietary caffeine samples.
enum HealthLogger {
    enum HealthError: LocalizedError {
        case unavailable
        case denied

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Health data isn't available on this device."
            case .denied:
                return "Health access is off. Enable Caffeine in Settings → Health → Data Access."
            }
        }
    }

    private static let store = HKHealthStore()

    /// Saves one drink to Health, asking for permission on first use.
    static func log(_ drink: CoffeeDrink, at date: Date = .now) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }

        let caffeine = HKQuantityType(.dietaryCaffeine)
        try await store.requestAuthorization(toShare: [caffeine], read: [])
        guard store.authorizationStatus(for: caffeine) == .sharingAuthorized else {
            throw HealthError.denied
        }

        let sample = HKQuantitySample(
            type: caffeine,
            quantity: HKQuantity(unit: .gramUnit(with: .milli),
                                 doubleValue: drink.caffeineMilligrams),
            start: date,
            end: date,
            metadata: [HKMetadataKeyFoodType: drink.name]
        )
        try await store.save(sample)
    }
}

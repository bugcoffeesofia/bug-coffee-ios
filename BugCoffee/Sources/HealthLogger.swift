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

/// The slice of `HKHealthStore` the logger needs — a seam so unit tests can
/// stand in for Health without a permission prompt.
protocol CaffeineHealthStore {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func save(_ object: HKObject) async throws
}

/// The real Health database.
struct SystemHealthStore: CaffeineHealthStore {
    static let shared = SystemHealthStore()
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        store.authorizationStatus(for: type)
    }

    func save(_ object: HKObject) async throws {
        try await store.save(object)
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

    /// Saves one drink to Health, asking for permission on first use.
    static func log(_ drink: CoffeeDrink, at date: Date = .now,
                    store: CaffeineHealthStore = SystemHealthStore.shared) async throws {
        guard store.isHealthDataAvailable else { throw HealthError.unavailable }

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

import SwiftUI

/// Tap a coffee to save its caffeine to Apple Health straight from the wrist.
/// Uses the same `HealthLogger` as the phone; watchOS asks for Health
/// permission on first log and the sample syncs back to the paired iPhone.
struct WatchLogView: View {
    @State private var isLogging = false
    @State private var result: String?
    @State private var loggingDrink: CoffeeDrink?

    var body: some View {
        List {
            ForEach(CoffeeDrink.allCases) { drink in
                Button {
                    log(drink)
                } label: {
                    HStack {
                        Text(drink.name)
                        Spacer()
                        if loggingDrink == drink {
                            ProgressView()
                        } else {
                            Text("\(Int(drink.caffeineMilligrams)) mg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isLogging)
            }

            if let result {
                Text(result)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Log caffeine")
    }

    private func log(_ drink: CoffeeDrink) {
        guard !isLogging else { return }
        isLogging = true
        loggingDrink = drink
        result = nil
        Task {
            defer {
                isLogging = false
                loggingDrink = nil
            }
            do {
                try await HealthLogger.log(drink)
                result = "\(drink.name) logged to Health ☕️"
            } catch {
                result = error.localizedDescription
            }
        }
    }
}

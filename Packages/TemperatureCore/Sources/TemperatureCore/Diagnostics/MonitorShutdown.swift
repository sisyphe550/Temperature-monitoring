import Foundation

public struct ShutdownStepResult: Sendable, Equatable {
    public let name: String
    public let completed: Bool

    public init(name: String, completed: Bool) {
        self.name = name
        self.completed = completed
    }
}

public struct ShutdownResult: Sendable, Equatable {
    public let stepResults: [ShutdownStepResult]
    public let incompleteSteps: [String]

    public init(stepResults: [ShutdownStepResult]) {
        self.stepResults = stepResults
        incompleteSteps = stepResults.filter { !$0.completed }.map(\.name)
    }
}

public enum MonitorShutdown {
    public static func run(
        budgetMS: Int,
        steps: [(name: String, action: () async -> Bool)]
    ) async -> ShutdownResult {
        let deadline = Date().addingTimeInterval(Double(budgetMS) / 1000)
        var results: [ShutdownStepResult] = []

        for step in steps {
            if Date() >= deadline {
                results.append(ShutdownStepResult(name: step.name, completed: false))
                continue
            }

            let completed = await step.action()
            results.append(ShutdownStepResult(name: step.name, completed: completed))
        }

        return ShutdownResult(stepResults: results)
    }
}

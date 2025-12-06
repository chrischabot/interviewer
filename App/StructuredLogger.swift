import Foundation

/// Lightweight logger that prints in a fixed-width, agent-friendly format:
/// `HH:mm:ss | Component           | Message`
enum StructuredLogger {
    private static let componentWidth = 22
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let formatterQueue = DispatchQueue(label: "interviewer.logger.formatter")

    static func log(component: String, message: String) {
        let timestamp = formatterQueue.sync {
            formatter.string(from: Date())
        }

        let trimmed = component.count > componentWidth
            ? String(component.prefix(componentWidth))
            : component

        let paddedComponent = trimmed.padding(toLength: componentWidth, withPad: " ", startingAt: 0)
        print("\(timestamp) | \(paddedComponent) | \(message)")
    }
}

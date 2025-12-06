import Foundation
import SwiftUI

// MARK: - Generic Error Helper

/// Simple error wrapper for string messages
struct GenericError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - App Error

/// Centralized error type with recovery guidance and user-friendly messages
enum AppError: Error, LocalizedError, Identifiable {
    case apiKeyMissing
    case apiKeyInvalid
    case networkUnavailable
    case connectionFailed(underlying: Error?)
    case connectionLost(canReconnect: Bool)
    case requestFailed(underlying: Error)
    case generationFailed(task: String, underlying: Error)
    case saveFailed(what: String, underlying: Error)
    case notFound(what: String)
    case unknown(underlying: Error)

    var id: String {
        switch self {
        case .apiKeyMissing: return "api_key_missing"
        case .apiKeyInvalid: return "api_key_invalid"
        case .networkUnavailable: return "network_unavailable"
        case .connectionFailed: return "connection_failed"
        case .connectionLost: return "connection_lost"
        case .requestFailed: return "request_failed"
        case .generationFailed(let task, _): return "generation_failed_\(task)"
        case .saveFailed(let what, _): return "save_failed_\(what)"
        case .notFound(let what): return "not_found_\(what)"
        case .unknown: return "unknown"
        }
    }

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API Key Required"
        case .apiKeyInvalid:
            return "Invalid API Key"
        case .networkUnavailable:
            return "No Internet Connection"
        case .connectionFailed:
            return "Connection Failed"
        case .connectionLost(let canReconnect):
            return canReconnect ? "Connection Lost" : "Session Ended"
        case .requestFailed:
            return "Request Failed"
        case .generationFailed(let task, _):
            return "\(task.capitalized) Failed"
        case .saveFailed(let what, _):
            return "Couldn't Save \(what.capitalized)"
        case .notFound(let what):
            return "\(what.capitalized) Not Found"
        case .unknown:
            return "Something Went Wrong"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .apiKeyMissing:
            return "Add your OpenAI API key in Settings to use the app."
        case .apiKeyInvalid:
            return "Your API key appears to be invalid. Check that you've entered it correctly in Settings."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .connectionFailed(let underlying):
            if let message = underlying?.localizedDescription {
                return "Could not connect to OpenAI: \(message). Check your connection and try again."
            }
            return "Could not connect to OpenAI. Check your internet connection and try again."
        case .connectionLost(let canReconnect):
            if canReconnect {
                return "The connection was interrupted. You can try reconnecting to resume."
            }
            return "The session has ended and cannot be resumed."
        case .requestFailed(let underlying):
            return "The request couldn't be completed: \(underlying.localizedDescription)"
        case .generationFailed(_, let underlying):
            return "Generation failed: \(underlying.localizedDescription). Try again or check your API key."
        case .saveFailed(_, let underlying):
            return "Save failed: \(underlying.localizedDescription). Your data may not have been saved."
        case .notFound(let what):
            return "The \(what.lowercased()) you're looking for doesn't exist or has been deleted."
        case .unknown(let underlying):
            return "An unexpected error occurred: \(underlying.localizedDescription)"
        }
    }

    /// Available recovery actions for this error
    var recoveryActions: [RecoveryAction] {
        switch self {
        case .apiKeyMissing, .apiKeyInvalid:
            return [.openSettings, .dismiss]
        case .networkUnavailable, .connectionFailed:
            return [.retry, .dismiss]
        case .connectionLost(let canReconnect):
            return canReconnect ? [.reconnect, .dismiss] : [.dismiss]
        case .requestFailed, .generationFailed:
            return [.retry, .dismiss]
        case .saveFailed:
            return [.retry, .dismiss]
        case .notFound:
            return [.goBack, .dismiss]
        case .unknown:
            return [.retry, .dismiss]
        }
    }

    /// Primary action (first button shown)
    var primaryAction: RecoveryAction {
        recoveryActions.first ?? .dismiss
    }

    /// Icon for the error
    var icon: String {
        switch self {
        case .apiKeyMissing, .apiKeyInvalid:
            return "key.slash"
        case .networkUnavailable:
            return "wifi.slash"
        case .connectionFailed, .connectionLost:
            return "antenna.radiowaves.left.and.right.slash"
        case .requestFailed, .generationFailed:
            return "exclamationmark.triangle"
        case .saveFailed:
            return "externaldrive.badge.xmark"
        case .notFound:
            return "magnifyingglass"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// Create from any Error
    static func from(_ error: Error, context: ErrorContext = .unknown) -> AppError {
        // Already an AppError
        if let appError = error as? AppError {
            return appError
        }

        // OpenAI errors
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .noAPIKey:
                return .apiKeyMissing
            case .httpError(let code, _) where code == 401:
                return .apiKeyInvalid
            case .networkError:
                return .networkUnavailable
            default:
                return context.wrap(openAIError)
            }
        }

        // Realtime errors
        if let realtimeError = error as? RealtimeClientError {
            switch realtimeError {
            case .noAPIKey:
                return .apiKeyMissing
            case .connectionFailed:
                return .connectionFailed(underlying: realtimeError)
            case .notConnected:
                return .connectionLost(canReconnect: true)
            default:
                return context.wrap(realtimeError)
            }
        }

        // URL errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .connectionFailed(underlying: urlError)
            default:
                return context.wrap(urlError)
            }
        }

        // Generic fallback
        return context.wrap(error)
    }
}

// MARK: - Error Context

/// Context for better error categorization
enum ErrorContext {
    case planGeneration
    case interviewConnection
    case analysisGeneration
    case draftGeneration
    case saving(what: String)
    case unknown

    func wrap(_ error: Error) -> AppError {
        switch self {
        case .planGeneration:
            return .generationFailed(task: "plan generation", underlying: error)
        case .interviewConnection:
            return .connectionFailed(underlying: error)
        case .analysisGeneration:
            return .generationFailed(task: "analysis", underlying: error)
        case .draftGeneration:
            return .generationFailed(task: "draft", underlying: error)
        case .saving(let what):
            return .saveFailed(what: what, underlying: error)
        case .unknown:
            return .unknown(underlying: error)
        }
    }
}

// MARK: - Recovery Action

enum RecoveryAction: String, Identifiable {
    case retry
    case reconnect
    case openSettings
    case goBack
    case dismiss

    var id: String { rawValue }

    var label: String {
        switch self {
        case .retry: return "Try Again"
        case .reconnect: return "Reconnect"
        case .openSettings: return "Open Settings"
        case .goBack: return "Go Back"
        case .dismiss: return "OK"
        }
    }

    var icon: String? {
        switch self {
        case .retry: return "arrow.clockwise"
        case .reconnect: return "antenna.radiowaves.left.and.right"
        case .openSettings: return "gear"
        case .goBack: return "chevron.left"
        case .dismiss: return nil
        }
    }

    var role: ButtonRole? {
        switch self {
        case .dismiss: return .cancel
        default: return nil
        }
    }

    var isDestructive: Bool {
        false
    }
}

// MARK: - Error Alert View Modifier

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    let onAction: (RecoveryAction) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                error?.errorDescription ?? "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                ),
                presenting: error
            ) { appError in
                ForEach(appError.recoveryActions) { action in
                    Button(action.label, role: action.role) {
                        onAction(action)
                        if action == .dismiss {
                            error = nil
                        }
                    }
                }
            } message: { appError in
                Text(appError.recoverySuggestion ?? "Please try again.")
            }
    }
}

extension View {
    /// Show an error alert with recovery actions
    func errorAlert(_ error: Binding<AppError?>, onAction: @escaping (RecoveryAction) -> Void) -> some View {
        modifier(ErrorAlertModifier(error: error, onAction: onAction))
    }
}

// MARK: - Error Banner View

/// A non-modal error banner for transient errors
struct ErrorBanner: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.icon)
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Error")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer()

            if let onRetry, error.primaryAction == .retry {
                Button {
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

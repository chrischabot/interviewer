import SwiftUI
import SwiftData

@main
struct InterviewerApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Plan.self,
                Section.self,
                Question.self,
                InterviewSession.self,
                Utterance.self,
                NotesStateModel.self,
                AnalysisSummaryModel.self,
                Draft.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppState.shared)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
        #endif
    }
}

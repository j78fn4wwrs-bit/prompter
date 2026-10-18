import SwiftUI
import SwiftData

@main
struct PrompterApp: App {
    @StateObject private var store = ProStore()

    var body: some Scene {
        WindowGroup {
            ScriptListView()
                .environmentObject(store)
                .task { await store.start() }
        }
        .modelContainer(for: Script.self)
    }
}

import SwiftUI

@main
struct HighLitApp: App {

    @State private var viewModel = RecordingViewModel()

    init() {
        WatchConnectivityService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RecordingView(viewModel: viewModel)
                .onAppear {
                    WatchConnectivityService.shared.onSaveRequested = { [viewModel] in
                        viewModel.saveHighlight()
                    }
                }
        }
    }
}

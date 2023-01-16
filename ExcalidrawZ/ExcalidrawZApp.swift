//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import Sparkle

@main
@MainActor
struct ExcalidrawZApp: App {
    let store = AppStore(state: AppState(),
                         reducer: appReducer,
                         environment: AppEnvironment())
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    
    @Environment(\.scenePhase) var scenePhase
    
    @State private var timer = Timer.publish(every: 30, on: .main, in: .default).autoconnect()
    
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .onReceive(timer) { _ in
                    store.send(.saveCoreData, log: false)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 500)
        #endif
        .onChange(of: scenePhase) { _ in
            //            store.send(.saveCoreData)
        }
    }
}

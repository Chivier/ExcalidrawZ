//
//  WebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import OSLog
import QuartzCore

class ExcalidrawWebView: WKWebView {
    var shouldHandleInput = false
    var toolbarActionHandler: (Int) -> Void
    var toolbarActionHandler2: (Character) -> Void
    
    init(
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        toolbarActionHandler: @escaping (Int) -> Void,
        toolbarActionHandler2: @escaping (Character) -> Void
    ) {
        self.toolbarActionHandler = toolbarActionHandler
        self.toolbarActionHandler2 = toolbarActionHandler2
        super.init(frame: frame, configuration: configuration)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func keyDown(with event: NSEvent) {
        if shouldHandleInput,
           let char = event.characters {
            if let num = Int(char), num >= 0, num <= 9 {
                self.toolbarActionHandler(num)
            } else if ExcalidrawTool.allCases.compactMap({$0.keyEquivalent}).contains(where: {$0 == Character(char)}) {
                self.toolbarActionHandler2(Character(char))
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

struct ExcalidrawView {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var toolState: ToolState

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebView")
    
    @Binding var isLoading: Bool
    @Binding var isLoadingFile: Bool
    
    var onError: (Error) -> Void
    
    // TODO: isLoadingFile is not used yet.
    init(isLoadingPage: Binding<Bool>, isLoadingFile: Binding<Bool>, onError: @escaping (Error) -> Void) {
        self._isLoading = isLoadingPage
        self._isLoadingFile = isLoadingFile
        self.onError = onError
    }
}

#if os(macOS)
extension ExcalidrawView: NSViewRepresentable {

    func makeNSView(context: Context) -> ExcalidrawWebView {
        return context.coordinator.webView
    }
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        let webView = context.coordinator.webView
        context.coordinator.parent = self
        exportState.excalidrawWebCoordinator = context.coordinator
        fileState.excalidrawWebCoordinator = context.coordinator
        guard !webView.isLoading else { return }
        Task {
            do {
                if appPreference.excalidrawAppearance == .auto {
                    try await context.coordinator.changeColorMode(dark: colorScheme == .dark)
                } else {
                    try await context.coordinator.changeColorMode(dark: appPreference.excalidrawAppearance.colorScheme ?? colorScheme == .dark)
                }
            } catch {
                self.onError(error)
            }
        }
        Task {
            do {
                try await context.coordinator.loadFile(from: fileState.currentFile)
            } catch {
                self.onError(error)
            }
        }
        if context.coordinator.lastTool != toolState.activatedTool {
            Task {
                do {
                    if let rawValue = toolState.activatedTool?.rawValue {
                        if rawValue < 10 {
                            try await context.coordinator.toggleToolbarAction(key: rawValue)
                        } else if let keyEquivalent = toolState.activatedTool?.keyEquivalent {
                            try await context.coordinator.toggleToolbarAction(key: keyEquivalent)
                        }
                    }
                } catch {
                    self.onError(error)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

#elseif os(iOS)

#endif
//
//  LibraryViewModel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import SwiftUI

class LibraryViewModel: ObservableObject {
    @Published private(set) var libraryViewID: String = UUID().uuidString
    
    
    public func forceLibraryViewUpdate() {
        self.libraryViewID = UUID().uuidString
    }
}

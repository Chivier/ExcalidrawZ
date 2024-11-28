//
//  ExcalidrawFileDocument.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/10.
//

import SwiftUI
import UniformTypeIdentifiers

extension ExcalidrawFile: FileDocument {
    static var readableContentTypes: [UTType] = [.text, .png, .svg, .excalidrawFile, .excalidrawPNG, .excalidrawSVG]
    static var writableContentTypes: [UTType] = [.excalidrawFile, .excalidrawPNG, .excalidrawSVG, .png, .svg,]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            struct GetFileContentError: LocalizedError {
                var errorDescription: String? { "Get file contents failed." }
            }
            throw GetFileContentError()
        }
        if configuration.contentType == .png {
            if let file = ExcalidrawPNGDecoder().decode(from: data) {
                self = file
                return
            }
        } else if configuration.contentType == .svg {
            if let file = ExcalidrawSVGDecoder().decode(from: data) {
               self = file
               return
           }
        }
        self = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self.content = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content ?? Data())
    }
}


fileprivate func isValidJSON(_ data: Data) -> Bool {
    guard let string = String(data: data, encoding: .utf8) else {
        return false
    }
    guard string.hasPrefix("[") || string.hasPrefix("{") else {
        return false
    }
    do {
        _ = try JSONSerialization.jsonObject(with: data, options: [])
        return true
    } catch {
        return false
    }
}
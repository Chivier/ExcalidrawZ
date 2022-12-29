//
//  AppFileManager.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import Combine
import OSLog

class AppFileManager: ObservableObject {
    static let shared = AppFileManager()
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                        category: "AppFileManager")
    
    let fileManager = FileManager.default
    let rootDir = try! FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
    
    var assetDir: URL {
        rootDir.appendingPathComponent("assets", conformingTo: .directory)
    }
        
    @Published private(set) var assetFiles: [FileInfo] = []

    lazy var monitor: DirMonitor = DirMonitor(dir: assetDir, queue: .init(label: "com.chocoford.ExcaliDrawZ-DirMonitor"))
    
    var monitorCancellable: AnyCancellable? = nil
    
    init() {
        // create asset dir if needed.
        do {
            try fileManager.createDirectory(at: assetDir, withIntermediateDirectories: true)
        } catch {
            dump(error)
        }
        if !monitor.start() {
            fatalError("Dir monitor starts failed.")
        }
        monitorCancellable = monitor.dirWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.loadFiles()
            }
    }
}

extension AppFileManager {
    func loadAssets() -> [FileInfo] {
        do {
            return try fileManager
                .contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil)
                .compactMap { FileInfo(from: $0) }
                .filter { $0.fileExtension == "excalidraw" }
                .sorted { $0.updatedAt ?? .distantPast > $1.updatedAt ?? .distantPast}
        } catch {
            return []
        }
    }
    
    func loadFiles() {
        do {
            assetFiles = try fileManager
                .contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil)
                .compactMap { FileInfo(from: $0) }
                .filter { $0.fileExtension == "excalidraw" }
                .sorted { $0.updatedAt ?? .distantPast > $1.updatedAt ?? .distantPast}
        } catch {
            assetFiles = []
        }
    }
    
    func generateNewFileName() -> URL {
        var name = assetDir.appending(path: "Untitled").appendingPathExtension("excalidraw")
        var i = 1
        while fileManager.fileExists(atPath: name.path(percentEncoded: false)) {
            name = assetDir.appending(path: "Untitled \(i)").appendingPathExtension("excalidraw")
            i += 1
        }
        return name
    }
    
    @MainActor
    func createNewFile() -> URL? {
        guard let template = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { return nil }
        let desURL = generateNewFileName()
        do {
            let data = try Data(contentsOf: template)
            fileManager.createFile(atPath: desURL.path(percentEncoded: false), contents: data)
            self.assetFiles.insert(FileInfo(from: desURL), at: 0)
            logger.info("create new file done. \(desURL.lastPathComponent)")
            return desURL
        } catch {
            dump(error)
            return nil
        }
    }
    
    func updateFile(_ file: URL, from tempFile: URL) {
        do {
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tempFile, to: file)
        } catch {
            logger.error("\(error)")
        }
    }
    
    func renameFile(_ url: URL, to name: String) throws -> URL {
        guard let index = self.assetFiles.firstIndex(where: {
            $0.url == url
        }) else {
            throw RenameError.notFound
        }
        let newURL = url.deletingLastPathComponent().appending(path: name).appendingPathExtension(url.pathExtension)
        try FileManager.default.moveItem(at: url, to: newURL)
        self.assetFiles[index].url = newURL
        self.assetFiles[index].name = name
        return newURL
    }
}

struct FileInfo: Identifiable, Hashable {
    var url: URL
    
    var name: String?
    var fileExtension: String?
    var createdAt: Date?
    var updatedAt: Date?
    var size: String?
    
    var id: String {
        url.path(percentEncoded: false)
    }
    
    init(url: URL, name: String? = nil, fileExtension: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, size: String? = nil) {
        self.url = url
        self.name = name
        self.fileExtension = fileExtension
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.size = size
    }
    
    init(from url: URL) {
        self.url = url
        if let name = url.lastPathComponent.split(separator: ".").first {
            self.name = String(name)
        }
        
        self.fileExtension = url.pathExtension
        
        let path = url.path(percentEncoded: false)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            // MARK: Created At
            if let createdAt = attributes[FileAttributeKey.creationDate] as? Date {
                self.createdAt = createdAt
            }
            
            // MARK: Updated At
            if let updatedAt = attributes[FileAttributeKey.modificationDate] as? Date {
                self.updatedAt = updatedAt
            }
            
            // MARK: Size
            if let size = attributes[FileAttributeKey.size] as? Double {
                let fileKB = size / 1024
                if fileKB > 1024 {
                    let fileMB: Double = fileKB / 1024
                    self.size = String(format: "%.1fMB", fileMB)
                } else {
                    self.size = String(format: "%.1fKB", fileKB)
                }
            }
        } catch {
            dump(error)
        }
    }

}

#if DEBUG
extension FileInfo {
    static let preview: FileInfo = .init(from: Bundle.main.url(forResource: "template", withExtension: "excalidraw")!)
}
#endif

class DirMonitor {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DirMonitor")
    init(dir: URL, queue: DispatchQueue) {
        self.dir = dir
        self.queue = queue
    }
    
    let dirWillChange: CurrentValueSubject<[(url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId)], Never> = .init([])

    deinit {
        // The stream has a reference to us via its `info` pointer. If the
        // client releases their reference to us without calling `stop`, that
        // results in a dangling pointer. We detect this as a programming error.
        // There are other approaches to take here (for example, messing around
        // with weak, or forming a retain cycle that’s broken on `stop`), but
        // this approach:
        //
        // * Has clear rules
        // * Is easy to implement
        // * Generate a sensible debug message if the client gets things wrong
        precondition(self.stream == nil, "released a running monitor")
        // I added this log line as part of my testing of the deallocation path.
        logger.info("did deinit")
    }

    let dir: URL
    let queue: DispatchQueue

    private var stream: FSEventStreamRef? = nil

    func start() -> Bool {
        precondition(self.stream == nil, "started a running monitor")

        // Set up our context.
        //
        // `FSEventStreamCallback` is a C function, so we pass `self` to the
        // `info` pointer so that it get call our `handleUnsafeEvents(…)`
        // method.  This involves the standard `Unmanaged` dance:
        //
        // * Here we set `info` to an unretained pointer to `self`.
        // * Inside the function we extract that pointer as `obj` and then use
        //   that to call `handleUnsafeEvents(…)`.

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        // Create the stream.
        //
        // In this example I wanted to show how to deal with raw string paths,
        // so I’m not taking advantage of `kFSEventStreamCreateFlagUseCFTypes`
        // or the even cooler `kFSEventStreamCreateFlagUseExtendedData`.

        guard let stream = FSEventStreamCreate(nil, { (stream, info, numEvents, eventPaths, eventFlags, eventIds) in
                let obj = Unmanaged<DirMonitor>.fromOpaque(info!).takeUnretainedValue()
                obj.handleUnsafeEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags, eventIDs: eventIds)
            },
            &context,
            [self.dir.path as NSString] as NSArray,
            UInt64(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return false
        }
        self.stream = stream

        // Now that we have a stream, schedule it on our target queue.

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            self.stream = nil
            return false
        }
        return true
    }

    private func handleUnsafeEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIDs: UnsafePointer<FSEventStreamEventId>) {
        // This takes the low-level goo from the C callback, converts it to
        // something that makes sense for Swift, and then passes that to
        // `handle(events:…)`.
        //
        // Note that we don’t need to do any rebinding here because this data is
        // coming C as the right type.
        let pathsBase = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let pathsBuffer = UnsafeBufferPointer(start: pathsBase, count: numEvents)
        let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: numEvents)
        let eventIDsBuffer = UnsafeBufferPointer(start: eventIDs, count: numEvents)
        // As `zip(_:_:)` only handles two sequences, I map over the index.
        let events = (0..<numEvents).map { i -> (url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId) in
            let path = pathsBuffer[i]
            // We set `isDirectory` to true because we only generate directory
            // events (that is, we don’t pass
            // `kFSEventStreamCreateFlagFileEvents` to `FSEventStreamCreate`.
            // This is generally the best way to use FSEvents, but if you decide
            // to take advantage of `kFSEventStreamCreateFlagFileEvents` then
            // you’ll need to code to `isDirectory` correctly.
            let url: URL = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
            return (url, flagsBuffer[i], eventIDsBuffer[i])
        }
        self.handle(events: events)
    }

    private func handle(events: [(url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId)]) {
        // In this example we just print the events with get, prefixed by a
        // count so that we can see the batching in action.
//        logger.info("\(events.count)")
//        for (url, flags, eventID) in events {
//            logger.info("\(eventID) \(flags) \(url.path)")
//        }
        dirWillChange.send(events)
    }

    func stop() {
        guard let stream = self.stream else {
            return          // We accept redundant calls to `stop`.
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }
}
import Foundation
import CoreServices

// MARK: - FSEvents File Watcher

final class FileWatcher {

    static let shared = FileWatcher()

    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.danielzhang.shelve.fsevents",
                                     qos: .utility)

    // Callback called after debounce when changes are detected
    var onChange: (() -> Void)?

    // MARK: - Start / Stop

    func start(watching urls: [URL]) {
        stop()

        let paths = urls.map { $0.path as CFString } as CFArray
        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.initialize(to: FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        ))
        defer { context.deallocate() }

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents(count: numEvents, paths: eventPaths)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,   // latency in seconds
            UInt32(kFSEventStreamCreateFlagUseCFTypes |
                   kFSEventStreamCreateFlagFileEvents |
                   kFSEventStreamCreateFlagIgnoreSelf)
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    // MARK: - Debounced handler

    private func handleEvents(count: Int, paths: UnsafeMutableRawPointer?) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 3.0, execute: work)
    }
}

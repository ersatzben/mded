import Foundation

/// Watches one file for changes made by other processes and calls `onChange`
/// (debounced, on the main queue). Survives atomic saves, where the editor
/// writes a new file and renames it over the old one, by re-opening the path.
///
/// `@unchecked Sendable`: every callback, and all state, lives on the main queue.
final class FileChangeMonitor: @unchecked Sendable {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var reopenAttempts = 0

    private static let debounce: TimeInterval = 0.3

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Mid-replace the path can briefly not exist; give it a moment.
            if reopenAttempts < 5 {
                reopenAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
            }
            return
        }
        reopenAttempts = 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self, unowned source] in
            guard let self else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // The inode we hold is gone or moved; watch whatever is at the path now.
                source.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start() }
            }
            self.scheduleChange()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }
}

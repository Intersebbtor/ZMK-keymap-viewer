import Foundation

class FileMonitor {
    private var fileURL: URL
    private var process:Process?

    init(filePath: String) {
        self.fileURL = URL(fileURLWithPath: filePath)
    }

    func startMonitoring() {
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(fileURL.path, O_EVTONLY), eventMask: .all, queue: DispatchQueue.main)

        source.setEventHandler { [weak self] in
            print("File changed: \(self?.fileURL.lastPathComponent ?? "")")
            self?.fileDidChange()
        }

        source.setCancelHandler { [weak self] in
            close(fileDescriptor)
        }
        source.resume()
    }

    private func fileDidChange() {
        // Handle the file change event
        print("File at \(fileURL.path) has changed")
    }
}
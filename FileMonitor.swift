import Foundation

class FileMonitor {
    private var fileURL: URL
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    
    var onFileChange: (() -> Void)?
    
    init(filePath: String) {
        self.fileURL = URL(fileURLWithPath: filePath)
    }
    
    func startMonitoring() {
        stopMonitoring()  // Clean up any existing monitor
        
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open file for monitoring: \(fileURL.path)")
            return
        }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main
        )
        
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            print("File changed: \(self.fileURL.lastPathComponent)")
            self.onFileChange?()
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        
        source?.resume()
        print("Started monitoring: \(fileURL.path)")
    }
    
    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
    
    deinit {
        stopMonitoring()
    }
}
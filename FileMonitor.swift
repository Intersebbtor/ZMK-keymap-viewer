import Foundation

class FileMonitor {
    private var fileURL: URL
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var isMonitoring = false
    
    var onFileChange: (() -> Void)?
    
    init(filePath: String) {
        self.fileURL = URL(fileURLWithPath: filePath)
        print("[FileMonitor] Created for: \\(filePath)")
    }
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("[FileMonitor] Already monitoring, skipping")
            return
        }
        
        stopMonitoring()  // Clean up any existing monitor
        
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[FileMonitor] Failed to open file for monitoring: \\(fileURL.path)")
            return
        }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main
        )
        
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            print("[FileMonitor] File changed: \\(self.fileURL.lastPathComponent)")
            self.onFileChange?()
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            print("[FileMonitor] Cancelled, closing file descriptor")
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
            self.isMonitoring = false
        }
        
        source?.resume()
        isMonitoring = true
        print("[FileMonitor] Started monitoring: \\(fileURL.path)")
    }
    
    func stopMonitoring() {
        guard isMonitoring || source != nil else { return }
        print("[FileMonitor] Stopping monitoring")
        source?.cancel()
        source = nil
        isMonitoring = false
    }
    
    deinit {
        print("[FileMonitor] Deinit")
        stopMonitoring()
    }
}
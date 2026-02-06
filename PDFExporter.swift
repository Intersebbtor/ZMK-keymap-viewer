import SwiftUI
import AppKit
import PDFKit

// MARK: - PDF Export Configuration

struct PDFExportConfig {
    let columnsPerPage: Int = 2
    let layersPerPage: Int = 6  // 2 columns × 3 rows
    let pageMargin: CGFloat = 40
    let layerSpacing: CGFloat = 20
    let showRawBindings: Bool = true  // Show raw binding below alias
}

// MARK: - Printable Key View (for PDF)

struct PrintableKeyView: View {
    let binding: KeyBinding
    let isThumbKey: Bool
    let showRawBinding: Bool
    
    private var displayLabel: String {
        let text = binding.effectiveDisplayText
        // Wrap long text at first space if >8 chars
        if text.count > 8 {
            if let spaceIndex = text.firstIndex(of: " "),
               text.distance(from: text.startIndex, to: spaceIndex) <= 10 {
                var result = text
                result.replaceSubrange(spaceIndex...spaceIndex, with: "\n")
                return result
            }
        }
        return text
    }
    
    private var hasAlias: Bool {
        binding.alias != nil
    }
    
    var body: some View {
        ZStack {
            // Key background - dark mode style
            RoundedRectangle(cornerRadius: 6)
                .fill(keyBackgroundColor)
            
            // Key border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            
            // Key content
            VStack(spacing: 1) {
                // Main label (alias or display text)
                Text(displayLabel)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                
                // Show raw binding below alias if enabled
                if showRawBinding && hasAlias {
                    Text(binding.displayText)
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundColor(textColor.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(2)
        }
    }
    
    /// Determine text color based on background luminance
    private var textColor: Color {
        // Light backgrounds get black text, dark backgrounds get white
        switch keyBackgroundType {
        case .trans, .dark:
            return .white
        case .blue, .purple, .orange, .green, .red:
            return .black  // Colored backgrounds are lighter, use black text
        }
    }
    
    private enum KeyBackgroundType {
        case trans, red, blue, purple, orange, green, dark
    }
    
    private var keyBackgroundType: KeyBackgroundType {
        if binding.displayText == "▽" {
            return .trans
        } else if binding.displayText == "✕" {
            return .red
        } else if isThumbKey {
            return .blue
        } else if binding.displayText.contains("\n") {
            return .purple
        } else if binding.rawCode.hasPrefix("&mo") || binding.rawCode.hasPrefix("&to") || binding.rawCode.hasPrefix("&tog") {
            return .orange
        } else if ["BT", "RESET", "BOOT", "STUDIO"].contains(where: { binding.displayText.contains($0) }) {
            return .green
        }
        return .dark
    }
    
    private var keyBackgroundColor: Color {
        switch keyBackgroundType {
        case .trans:
            return Color(white: 0.3)
        case .red:
            return Color.red.opacity(0.7)
        case .blue:
            return Color.blue.opacity(0.6)
        case .purple:
            return Color.purple.opacity(0.6)
        case .orange:
            return Color.orange.opacity(0.7)
        case .green:
            return Color.green.opacity(0.6)
        case .dark:
            return Color(white: 0.2)
        }
    }
    
    private var fontSize: CGFloat {
        let text = displayLabel
        if text.count > 6 { return 7 }
        else if text.count > 4 { return 8 }
        else if text.count > 2 { return 9 }
        return 10
    }
}

// MARK: - Printable Layer Grid View

struct PrintableLayerGridView: View {
    let layer: KeymapLayer
    let layout: KeyboardLayout
    let showRawBindings: Bool
    
    private var keyWidth: CGFloat { 36 }
    private var keyHeight: CGFloat { 30 }
    private let keySpacing: CGFloat = 2
    private let splitGap: CGFloat = 16
    
    var body: some View {
        VStack(alignment: .center, spacing: keySpacing) {
            ForEach(0..<layout.rowCount, id: \.self) { rowIndex in
                rowView(for: rowIndex)
            }
        }
    }
    
    private func rowView(for rowIndex: Int) -> some View {
        let keysInRow = layout.keysPerRow[safe: rowIndex] ?? 0
        let maxKeysInRow = layout.keysPerRow.max() ?? 0
        let bindings = getBindingsForRow(rowIndex)
        let isThumbRow = rowIndex == layout.rowCount - 1 && layout.hasThumbCluster
        let halfCount = keysInRow / 2
        
        let keysDifference = maxKeysInRow - keysInRow
        let oneKeyWidth = keyWidth + keySpacing
        let extraGap = layout.isSplit && !isThumbRow && keysInRow < maxKeysInRow ? CGFloat(keysDifference) * oneKeyWidth : 0
        let baseGap = layout.isSplit ? (isThumbRow ? splitGap + 12 : splitGap) : 0
        let adjustedGap = baseGap + extraGap
        
        let rowContent: AnyView
        
        if layout.isSplit {
            rowContent = AnyView(
                HStack(spacing: keySpacing) {
                    // Left half
                    HStack(spacing: keySpacing) {
                        ForEach(0..<halfCount, id: \.self) { colIndex in
                            if let binding = bindings[safe: colIndex] {
                                PrintableKeyView(binding: binding, isThumbKey: isThumbRow, showRawBinding: showRawBindings)
                                    .frame(width: keyWidth, height: keyHeight)
                            }
                        }
                    }
                    
                    Spacer().frame(width: adjustedGap)
                    
                    // Right half
                    HStack(spacing: keySpacing) {
                        ForEach(halfCount..<keysInRow, id: \.self) { colIndex in
                            if let binding = bindings[safe: colIndex] {
                                PrintableKeyView(binding: binding, isThumbKey: isThumbRow, showRawBinding: showRawBindings)
                                    .frame(width: keyWidth, height: keyHeight)
                            }
                        }
                    }
                }
            )
        } else {
            rowContent = AnyView(
                HStack(spacing: keySpacing) {
                    ForEach(0..<keysInRow, id: \.self) { colIndex in
                        if let binding = bindings[safe: colIndex] {
                            PrintableKeyView(binding: binding, isThumbKey: isThumbRow, showRawBinding: showRawBindings)
                                .frame(width: keyWidth, height: keyHeight)
                        }
                    }
                }
            )
        }
        
        return rowContent
            .padding(.top, isThumbRow ? 4 : 0)
    }
    
    private func getBindingsForRow(_ row: Int) -> [KeyBinding] {
        layer.bindings.filter { $0.row == row }.sorted { $0.column < $1.column }
    }
}

// MARK: - Printable Layer Card

struct PrintableLayerCard: View {
    let layer: KeymapLayer
    let layerIndex: Int
    let layout: KeyboardLayout
    let showRawBindings: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Layer header - dark text on white bg
            HStack {
                Text("Layer \(layerIndex):")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                Text(layer.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            
            // Layer grid
            PrintableLayerGridView(layer: layer, layout: layout, showRawBindings: showRawBindings)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        )
    }
}

// MARK: - PDF Page View (Single Column)

struct PDFPageView: View {
    let keymap: Keymap
    let layers: [(index: Int, layer: KeymapLayer)]  // Layers for this page
    let pageNumber: Int
    let totalPages: Int
    let showRawBindings: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(keymap.layout.name)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("Page \(pageNumber) of \(totalPages)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 12)
            
            // Single column of layers
            VStack(spacing: 20) {
                ForEach(layers, id: \.index) { item in
                    PrintableLayerCard(
                        layer: item.layer,
                        layerIndex: item.index,
                        layout: keymap.layout,
                        showRawBindings: showRawBindings
                    )
                }
            }
            
            Spacer()
            
            // Footer
            HStack {
                Text("Generated by ZMK Keymap Viewer")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Date(), style: .date)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .frame(width: 612, height: 792)  // US Letter size in points
        .background(Color.white)
    }
}

// MARK: - PDF Exporter

@MainActor
class PDFExporter {
    
    static func export(keymap: Keymap, to directory: String = "Desktop", showRawBindings: Bool = true) {
        print("[PDFExporter] Starting export to \(directory)...")
        
        // Generate filename with timestamp to avoid conflicts
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(keymap.layout.name) Keymap \(timestamp).pdf"
            .replacingOccurrences(of: "/", with: "-")  // Sanitize
            .replacingOccurrences(of: ":", with: "-")
        
        // Get directory URL based on selection
        let searchPath: FileManager.SearchPathDirectory
        switch directory {
        case "Documents":
            searchPath = .documentDirectory
        case "Downloads":
            searchPath = .downloadsDirectory
        default:
            searchPath = .desktopDirectory
        }
        
        let directoryURL = FileManager.default.urls(for: searchPath, in: .userDomainMask).first!
        let fileURL = directoryURL.appendingPathComponent(filename)
        
        print("[PDFExporter] Will save to: \(fileURL.path)")
        
        if let pdfData = Self.generatePDF(keymap: keymap, showRawBindings: showRawBindings) {
            do {
                try pdfData.write(to: fileURL)
                print("[PDFExporter] Successfully exported to: \(fileURL.path)")
                
                // Open the PDF
                NSWorkspace.shared.open(fileURL)
                
                // Also reveal in Finder
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: directoryURL.path)
            } catch {
                print("[PDFExporter] Error writing PDF: \(error)")
            }
        } else {
            print("[PDFExporter] Failed to generate PDF data")
        }
    }
    
    static func generatePDF(keymap: Keymap, showRawBindings: Bool) -> Data? {
        print("[PDFExporter] Generating PDF with \(keymap.layers.count) layers...")
        
        let layersPerPage = 3  // Single column, 3 layers per page
        let totalLayers = keymap.layers.count
        let totalPages = (totalLayers + layersPerPage - 1) / layersPerPage
        
        print("[PDFExporter] Will create \(totalPages) page(s)")
        
        // Create indexed layer tuples
        let indexedLayers = keymap.layers.enumerated().map { (index: $0.offset, layer: $0.element) }
        
        // Split into pages
        var pages: [[(index: Int, layer: KeymapLayer)]] = []
        for pageIndex in 0..<totalPages {
            let startIdx = pageIndex * layersPerPage
            let endIdx = min(startIdx + layersPerPage, totalLayers)
            pages.append(Array(indexedLayers[startIdx..<endIdx]))
        }
        
        // Create PDF document
        let pdfDocument = PDFDocument()
        
        for (pageIndex, pageLayers) in pages.enumerated() {
            print("[PDFExporter] Rendering page \(pageIndex + 1)...")
            
            let pageView = PDFPageView(
                keymap: keymap,
                layers: pageLayers,
                pageNumber: pageIndex + 1,
                totalPages: totalPages,
                showRawBindings: showRawBindings
            )
            
            // Render view to image
            let renderer = ImageRenderer(content: pageView)
            renderer.scale = 2.0  // Retina quality
            
            if let nsImage = renderer.nsImage {
                print("[PDFExporter] Page \(pageIndex + 1) rendered: \(nsImage.size)")
                if let pdfPage = PDFPage(image: nsImage) {
                    pdfDocument.insert(pdfPage, at: pageIndex)
                } else {
                    print("[PDFExporter] Failed to create PDFPage from image")
                }
            } else {
                print("[PDFExporter] Failed to render page \(pageIndex + 1) to image")
            }
        }
        
        print("[PDFExporter] PDF generation complete, \(pdfDocument.pageCount) pages")
        return pdfDocument.dataRepresentation()
    }
}

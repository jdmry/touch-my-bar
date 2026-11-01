import AppKit

/// "Customize Bar…": drag the sections into order, and drag the flexible
/// space to choose which of them sit on the left and which on the right.
///
/// The list runs top to bottom for the bar's left to right — a vertical
/// list is what a Mac window reorders well, and the bar itself is too
/// small to drag things around on. Every drop applies straight away, so
/// the bar is the preview.
final class LayoutWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = LayoutWindowController()

    private enum Metrics {
        static let width: CGFloat = 340
        static let rowHeight: CGFloat = 30
        static let margin: CGFloat = 20
        static let spacing: CGFloat = 12
    }

    private static let rowType = NSPasteboard.PasteboardType("dev.ctoasap.touchmybar.layout-row")

    private var layout = BarLayout.current
    private let tableView = NSTableView()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Customize Bar"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        layout = BarLayout.current
        tableView.reloadData()
        window?.center()
        // A menu bar app is never frontmost on its own; without this the
        // window opens behind whatever was in use.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func build() {
        let intro = NSTextField(wrappingLabelWithString:
            "Drag to arrange. Top of the list is the left end of the bar. "
            + "Everything above Flexible Space sits on the left, everything below it on the right.")
        intro.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: .init("slot"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.rowType])
        tableView.draggingDestinationFeedbackStyle = .gap

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let reset = NSButton(title: "Restore Default", target: self, action: #selector(resetTapped))
        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.keyEquivalent = "\r"

        let buttons = NSStackView(views: [reset, NSView(), done])
        buttons.orientation = .horizontal

        let content = NSStackView(views: [intro, scrollView, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = Metrics.spacing
        content.edgeInsets = NSEdgeInsets(top: Metrics.margin, left: Metrics.margin,
                                          bottom: Metrics.margin, right: Metrics.margin)

        let rows = CGFloat(BarLayout.standard.slots.count)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Metrics.width),
            intro.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -2 * Metrics.margin),
            scrollView.widthAnchor.constraint(equalTo: intro.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: intro.widthAnchor),
            // Room for every row plus the inset style's padding, so nothing
            // ever has to scroll.
            scrollView.heightAnchor.constraint(equalToConstant: rows * (Metrics.rowHeight + 2) + 16),
        ])

        window?.contentView = content
    }

    // MARK: - Data

    func numberOfRows(in tableView: NSTableView) -> Int {
        layout.slots.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let image = NSImageView()
        let label = NSTextField(labelWithString: "")

        switch layout.slots[row] {
        case .section(let section):
            image.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil)
            label.stringValue = section.title
            // Kept in the list so the arrangement survives a move to a Mac
            // that does have it, but say why it will not show up.
            if section == .brightness, !SystemBrightness.isAvailable {
                label.stringValue += " (unavailable on this Mac)"
                label.textColor = .tertiaryLabelColor
            }
        case .space:
            image.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)
            image.contentTintColor = .secondaryLabelColor
            label.stringValue = "Flexible Space"
            label.textColor = .secondaryLabelColor
        }

        let handle = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal",
                                                accessibilityDescription: "Drag to reorder") ?? NSImage())
        handle.contentTintColor = .tertiaryLabelColor

        let row = NSStackView(views: [image, label, NSView(), handle])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 20),
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Dragging

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Between rows only; dropping onto one has no meaning here.
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let string = info.draggingPasteboard.string(forType: Self.rowType),
              let source = Int(string) else { return false }

        // `row` counts the dragged row still in place; once it is lifted
        // out, everything below it moves up one.
        let destination = source < row ? row - 1 : row
        guard destination != source else { return false }

        layout.move(from: source, to: destination)
        tableView.reloadData()
        BarLayout.current = layout
        return true
    }

    // MARK: - Actions

    @objc private func resetTapped() {
        layout = .standard
        tableView.reloadData()
        BarLayout.current = layout
    }

    @objc private func doneTapped() {
        window?.close()
    }
}

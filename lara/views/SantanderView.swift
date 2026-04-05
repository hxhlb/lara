//
//  SantanderView.swift
//  symlin2k
//
//  Created by ruter on 15.02.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVKit
import QuickLook

struct SantanderView: View {
    let startPath: String
    @State private var selectedmethod: method = .sbx
    @ObservedObject private var mgr = laramgr.shared

    init(startPath: String = "/") {
        self.startPath = startPath.isEmpty ? "/" : startPath
    }

    var body: some View {
        let ready = (selectedmethod == .vfs) ? mgr.vfsready : mgr.sbxready
        Group {
            if ready {
                SantanderBrowserSheet(startPath: startPath)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 36, weight: .semibold))
                    Text(selectedmethod == .vfs ? "VFS not ready" : "Sandbox escape not ready")
                        .font(.headline)
                    Text(selectedmethod == .vfs ? "Run exploit and VFS init first." : "Run exploit and SBX escape first.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            refreshSelectedMethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSelectedMethod()
        }
    }

    private func refreshSelectedMethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}

struct SantanderBrowserSheet: UIViewControllerRepresentable {
    let startPath: String
    @State private var selectedmethod: method = .sbx

    func makeUIViewController(context: Context) -> UINavigationController {
        let useSBX = (selectedmethod == .sbx)
        let root = SantanderPathListViewController(path: SantanderPath(path: startPath, isDirectory: true), useSBX: useSBX)
        return UINavigationController(rootViewController: root)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}

struct SantanderPath: Hashable {
    let path: String
    let lastPathComponent: String
    let isDirectory: Bool
    let contentType: UTType?

    var displayImage: UIImage? {
        if isDirectory { return UIImage(systemName: "folder.fill") }
        guard let type = contentType else { return UIImage(systemName: "doc") }
        if type.isSubtype(of: .text) { return UIImage(systemName: "doc.text") }
        if type.isSubtype(of: .image) { return UIImage(systemName: "photo") }
        if type.isSubtype(of: .audio) { return UIImage(systemName: "waveform") }
        if type.isSubtype(of: .movie) || type.isSubtype(of: .video) { return UIImage(systemName: "play") }
        return UIImage(systemName: "doc")
    }

    init(path: String, isDirectory: Bool) {
        self.path = path
        self.lastPathComponent = path == "/" ? "/" : (path as NSString).lastPathComponent
        self.isDirectory = isDirectory
        let ext = (path as NSString).pathExtension
        self.contentType = ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }
}

final class SantanderPathListViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private struct ClipboardItem {
        let path: String
        let isDirectory: Bool
        let name: String
    }

    private static var clipboard: ClipboardItem?

    private var unfilteredContents: [SantanderPath]
    private var renderedContents: [SantanderPath]
    private let currentPath: SantanderPath
    private let useSBX: Bool
    private var initialEmptyStateMessage: String?
    private var isSearching = false
    private var displayHiddenFiles = true

    init(path: SantanderPath, useSBX: Bool) {
        self.useSBX = useSBX
        let initialListing = Self.loadDirectoryContents(for: path, useSBX: useSBX)
        self.currentPath = path
        self.unfilteredContents = initialListing.items
        self.renderedContents = initialListing.items
        self.initialEmptyStateMessage = initialListing.emptyStateMessage
        super.init(style: .insetGrouped)
        self.title = path.path == "/" ? "/" : path.lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.title = currentPath.path == "/" ? "/" : currentPath.lastPathComponent

        setRightBarButton()

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        applyFilters()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.title = currentPath.path == "/" ? "/" : currentPath.lastPathComponent
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        renderedContents.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if shouldShowFooter() {
            return "This File Manager is very unreliable and overall shitty. For more information, look at the info button. \nIT MAY DISPLAY INACCURATE INFORMATION!"
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = renderedContents[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            guard let self else { return UIMenu() }
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copyItem(item)
            }
            let replaceAction = UIAction(
                title: "Replace With Clipboard",
                image: UIImage(systemName: "doc.on.clipboard"),
                attributes: (Self.clipboard == nil || !self.useSBX) ? [.disabled] : []
            ) { [weak self] _ in
                self?.replaceItem(item)
            }
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.confirmDelete(item)
            }
            return UIMenu(children: [copyAction, replaceAction, deleteAction])
        })
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let path = renderedContents[indexPath.row]
        return pathCellRow(forURL: path, displayFullPathAsSubtitle: isSearching)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let path = renderedContents[indexPath.row]
        if path.isDirectory {
            let vc = SantanderPathListViewController(path: path, useSBX: useSBX)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = SantanderFileReaderViewController(path: path, useSBX: useSBX)
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func applyFilters(query: String = "") {
        var items = unfilteredContents
        if !displayHiddenFiles {
            items = items.filter { !$0.lastPathComponent.starts(with: ".") }
        }
        if !query.isEmpty {
            items = items.filter {
                $0.lastPathComponent.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
            }
        }
        renderedContents = items
        updateEmptyState(query: query)
        tableView.reloadData()
    }

    private func updateEmptyState(query: String) {
        guard renderedContents.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let message: String
        if !query.isEmpty {
            message = "No matching items."
        } else if !displayHiddenFiles && !unfilteredContents.isEmpty {
            message = "No visible items. Enable \"Display hidden files\" to show dotfiles."
        } else {
            message = initialEmptyStateMessage ?? "Directory is empty."
        }

        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        tableView.backgroundView = label
    }

    private static func loadDirectoryContents(for path: SantanderPath, useSBX: Bool) -> (items: [SantanderPath], emptyStateMessage: String?) {
        guard path.isDirectory else { return ([], "Not a directory.") }

        let mgr = laramgr.shared
        if useSBX {
            guard mgr.sbxready else { return ([], "Sandbox escape not ready.") }
            return loadDirectoryContentsSBX(for: path)
        }

        guard mgr.vfsready else { return ([], "Not ready.") }
        guard let entries = mgr.vfslistdir(path: path.path) else {
            return ([], "Unable to list directory.")
        }

        let items = entries.map { entry in
            let name = entry.name
            let fullPath = path.path == "/" ? "/" + name : path.path + "/" + name
            return SantanderPath(path: fullPath, isDirectory: entry.isDir)
        }

        if items.isEmpty {
            return ([], "Directory is empty.")
        }

        return (items, nil)
    }

    private static func loadDirectoryContentsSBX(for path: SantanderPath) -> (items: [SantanderPath], emptyStateMessage: String?) {
        let fm = FileManager.default
        do {
            let entries = try fm.contentsOfDirectory(atPath: path.path)
            let items = entries.map { name in
                let fullPath = path.path == "/" ? "/" + name : path.path + "/" + name
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                return SantanderPath(path: fullPath, isDirectory: isDir.boolValue)
            }
            if items.isEmpty {
                return ([], "Directory is empty.")
            }
            return (items, nil)
        } catch {
            return ([], "Unable to list directory.")
        }
    }

    private static func isSBXSelected() -> Bool {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod") {
            return raw.uppercased() == "SBX"
        }
        return false
    }
    private func setRightBarButton() {
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeRightBarButton()
        )
        if shouldShowFooter() {
            let infoButton = UIBarButtonItem(
                image: UIImage(systemName: "info.circle"),
                style: .plain,
                target: self,
                action: #selector(showInfo)
            )
            navigationItem.rightBarButtonItems = [menuButton, infoButton]
        } else {
            navigationItem.rightBarButtonItems = [menuButton]
        }
    }

    private func makeRightBarButton() -> UIMenu {
        let pasteAction = UIAction(
            title: "Paste",
            image: UIImage(systemName: "doc.on.clipboard"),
            attributes: (Self.clipboard == nil || !useSBX) ? [.disabled] : []
        ) { [weak self] _ in
            self?.pasteClipboardItem()
        }
        let pasteReplaceAction = UIAction(
            title: "Paste (Replace)",
            image: UIImage(systemName: "doc.on.clipboard.fill"),
            attributes: (Self.clipboard == nil || !useSBX) ? [.disabled] : []
        ) { [weak self] _ in
            self?.pasteClipboardItem(replaceExisting: true)
        }
        let sortAZ = UIAction(title: "Sort A-Z", image: UIImage(systemName: "textformat")) { [weak self] _ in
            guard let self else { return }
            self.unfilteredContents.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let sortZA = UIAction(title: "Sort Z-A", image: UIImage(systemName: "textformat")) { [weak self] _ in
            guard let self else { return }
            self.unfilteredContents.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedDescending }
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let toggleHidden = UIAction(title: "Display hidden files", image: UIImage(systemName: "eye"), state: displayHiddenFiles ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.displayHiddenFiles.toggle()
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let goRoot = UIAction(title: "Go to Root", image: UIImage(systemName: "externaldrive")) { [weak self] _ in
            guard let self else { return }
            let vc = SantanderPathListViewController(path: SantanderPath(path: "/", isDirectory: true), useSBX: useSBX)
            self.navigationController?.setViewControllers([vc], animated: true)
        }
        let goHome = UIAction(title: "Go to Home", image: UIImage(systemName: "house")) { [weak self] _ in
            guard let self else { return }
            let vc = SantanderPathListViewController(path: SantanderPath(path: NSHomeDirectory(), isDirectory: true), useSBX: useSBX)
            self.navigationController?.setViewControllers([vc], animated: true)
        }
        let sortMenu = UIMenu(title: "Sort by..", image: UIImage(systemName: "arrow.up.arrow.down"), children: [sortAZ, sortZA])
        let viewMenu = UIMenu(title: "View", image: UIImage(systemName: "eye"), children: [toggleHidden])
        let goMenu = UIMenu(title: "Go to..", image: UIImage(systemName: "arrow.right"), children: [goRoot, goHome])
        return UIMenu(children: [pasteAction, pasteReplaceAction, sortMenu, viewMenu, goMenu])
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isSearching = !query.isEmpty
        applyFilters(query: query)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        applyFilters(query: "")
    }

    private func pathCellRow(forURL fsItem: SantanderPath, displayFullPathAsSubtitle useSubtitle: Bool = false) -> UITableViewCell {
        let pathName = fsItem.lastPathComponent
        let cell = UITableViewCell(style: useSubtitle ? .subtitle : .default, reuseIdentifier: nil)
        var conf = cell.defaultContentConfiguration()
        conf.text = pathName
        conf.image = fsItem.displayImage

        if pathName.first == "." {
            conf.textProperties.color = .gray
            conf.secondaryTextProperties.color = .gray
        }
        if useSubtitle {
            conf.secondaryText = fsItem.path
        }
        if fsItem.isDirectory {
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = conf
        return cell
    }

    private func shouldShowFooter() -> Bool {
        return !useSBX
    }

    @objc private func showInfo() {
        let msg = """
        This browser is powered by vfs namecache lookups, not full directory enumeration. Therefore, some folders (eg. /private/var) may appear empty unless entries are already cached.
        Symlinks may then also be shown as files even when their targets are directories.
        
        tldr; This File Manager is unreliable and sometimes completely inaccurate. If it works or not is basically 100% up to luck.
        """
        let alert = UIAlertController(title: "File Manager Info", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func copyItem(_ item: SantanderPath) {
        Self.clipboard = ClipboardItem(path: item.path, isDirectory: item.isDirectory, name: item.lastPathComponent)
        let alert = UIAlertController(title: "Copied", message: item.lastPathComponent, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        setRightBarButton()
    }

    private func pasteClipboardItem(replaceExisting: Bool = false) {
        guard useSBX else {
            let alert = UIAlertController(title: "Paste Unavailable", message: "Paste is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        guard let clip = Self.clipboard else { return }

        let destDir = currentPath.path
        if clip.isDirectory {
            if destDir == clip.path || destDir.hasPrefix(clip.path + "/") {
                let alert = UIAlertController(title: "Paste Failed", message: "Cannot paste a folder into itself.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }

        let baseDest = (destDir as NSString).appendingPathComponent(clip.name)
        let dest = replaceExisting ? baseDest : uniqueDestinationPath(base: baseDest)

        do {
            if replaceExisting && FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: clip.path, toPath: dest)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Paste Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func uniqueDestinationPath(base: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base) { return base }

        let dir = (base as NSString).deletingLastPathComponent
        let file = (base as NSString).lastPathComponent
        let ext = (file as NSString).pathExtension
        let stem = ext.isEmpty ? file : (file as NSString).deletingPathExtension

        var i = 1
        while true {
            let suffix = i == 1 ? " copy" : " copy \(i)"
            let newName = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate) { return candidate }
            i += 1
        }
    }

    private func reloadContents() {
        let listing = Self.loadDirectoryContents(for: currentPath, useSBX: useSBX)
        unfilteredContents = listing.items
        initialEmptyStateMessage = listing.emptyStateMessage
        applyFilters(query: navigationItem.searchController?.searchBar.text ?? "")
    }

    private func confirmDelete(_ item: SantanderPath) {
        let alert = UIAlertController(title: "Delete", message: "Delete \(item.lastPathComponent)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteItem(item)
        })
        present(alert, animated: true)
    }

    private func deleteItem(_ item: SantanderPath) {
        guard useSBX else {
            let alert = UIAlertController(title: "Delete Unavailable", message: "Delete is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        do {
            try FileManager.default.removeItem(atPath: item.path)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Delete Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func replaceItem(_ item: SantanderPath) {
        guard useSBX else {
            let alert = UIAlertController(title: "Replace Unavailable", message: "Replace is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        guard let clip = Self.clipboard else { return }
        if clip.isDirectory {
            if item.path == clip.path || item.path.hasPrefix(clip.path + "/") {
                let alert = UIAlertController(title: "Replace Failed", message: "Cannot replace with a folder into itself.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: item.path) {
                try FileManager.default.removeItem(atPath: item.path)
            }
            try FileManager.default.copyItem(atPath: clip.path, toPath: item.path)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Replace Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

final class SantanderFileReaderViewController: UIViewController, QLPreviewControllerDataSource {
    private let usingSBX: Bool
    private let path: SantanderPath
    private let textView = UITextView()
    private let imageView = UIImageView()
    private var playerVC: AVPlayerViewController?
    private var tempURL: URL?
    private var tempSize: Int64 = 0
    private var isEditingFile = false
    private var isEditableText = false
    private var editButton: UIBarButtonItem?

    init(path: SantanderPath, useSBX: Bool) {
        self.path = path
        self.usingSBX = useSBX
        super.init(nibName: nil, bundle: nil)
        self.title = path.lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label

        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true

        view.addSubview(textView)
        view.addSubview(imageView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        if usingSBX {
            let edit = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(toggleEdit))
            edit.isEnabled = false
            editButton = edit
            navigationItem.rightBarButtonItems = [
                edit,
                UIBarButtonItem(title: "Preview", style: .plain, target: self, action: #selector(showPreview)),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(showShare))
            ]
        } else {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "Preview", style: .plain, target: self, action: #selector(showPreview)),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(showShare))
            ]
        }

        loadFile()
    }

    private func loadFile() {
        let mgr = laramgr.shared
        if usingSBX {
            if let type = path.contentType {
                if type.isSubtype(of: .image) {
                    guard let data = readFileSBX(maxBytes: 8 * 1024 * 1024) else {
                        textView.text = "Failed to read file."
                        return
                    }
                    if let image = UIImage(data: data) {
                        imageView.image = image
                        imageView.isHidden = false
                        textView.isHidden = true
                        return
                    }
                }

                if type.isSubtype(of: .audio) || type.isSubtype(of: .movie) || type.isSubtype(of: .video) {
                    if prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) {
                        let player = AVPlayer(url: tempURL!)
                        let pvc = AVPlayerViewController()
                        pvc.player = player
                        addChild(pvc)
                        pvc.view.frame = view.bounds
                        pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                        view.addSubview(pvc.view)
                        pvc.didMove(toParent: self)
                        playerVC = pvc
                        player.play()
                        return
                    } else {
                        textView.text = "Failed to prepare media file."
                        return
                    }
                }
            }

            guard let data = readFileSBX(maxBytes: 2 * 1024 * 1024) else {
                textView.text = "Failed to read file."
                return
            }
            let rendered = render(data: data)
            textView.text = rendered.text
            setEditableText(rendered.isUtf8)
            return
        }

        if let type = path.contentType {
            if type.isSubtype(of: .image) {
                guard let data = mgr.vfsread(path: path.path, maxSize: 8 * 1024 * 1024) else {
                    textView.text = "Failed to read file."
                    return
                }
                if let image = UIImage(data: data) {
                    imageView.image = image
                    imageView.isHidden = false
                    textView.isHidden = true
                    return
                }
            }

            if type.isSubtype(of: .audio) || type.isSubtype(of: .movie) || type.isSubtype(of: .video) {
                if prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) {
                    let player = AVPlayer(url: tempURL!)
                    let pvc = AVPlayerViewController()
                    pvc.player = player
                    addChild(pvc)
                    pvc.view.frame = view.bounds
                    pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    view.addSubview(pvc.view)
                    pvc.didMove(toParent: self)
                    playerVC = pvc
                    player.play()
                    return
                } else {
                    textView.text = "Failed to prepare media file."
                    return
                }
            }
        }

        guard let data = mgr.vfsread(path: path.path, maxSize: 2 * 1024 * 1024) else {
            textView.text = "Failed to read file."
            return
        }
        let rendered = render(data: data)
        textView.text = rendered.text
    }

    @objc private func toggleEdit() {
        guard usingSBX, isEditableText else { return }
        if isEditingFile {
            saveEdits()
        } else {
            isEditingFile = true
            textView.isEditable = true
            textView.becomeFirstResponder()
            editButton?.title = "Save"
        }
    }

    private func saveEdits() {
        let data = Data(textView.text.utf8)
        do {
            try data.write(to: URL(fileURLWithPath: path.path), options: .atomic)
            isEditingFile = false
            textView.isEditable = false
            textView.resignFirstResponder()
            editButton?.title = "Edit"
            let alert = UIAlertController(title: "Saved", message: "File updated.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(title: "Save Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func readFileSBX(maxBytes: Int) -> Data? {
        let url = URL(fileURLWithPath: path.path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        if #available(iOS 13.4, *) {
            return try? handle.read(upToCount: maxBytes) ?? Data()
        }
        return handle.readData(ofLength: maxBytes)
    }

    private func fileSizeSBX() -> Int64? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private func render(data: Data) -> (text: String, isUtf8: Bool) {
        if let s = String(data: data, encoding: .utf8) {
            return (s, true)
        }
        let maxBytes = min(data.count, 8192)
        let hex = data.prefix(maxBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
        if data.count > maxBytes {
            return (hex + "\n... (" + String(data.count) + " bytes total)", false)
        }
        return (hex, false)
    }

    private func setEditableText(_ editable: Bool) {
        isEditableText = editable
        editButton?.isEnabled = editable
    }

    @objc private func showPreview() {
        guard prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) else {
            textView.text = "Failed to prepare preview."
            return
        }
        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    @objc private func showShare() {
        guard prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) else {
            textView.text = "Failed to prepare share."
            return
        }
        let av = UIActivityViewController(activityItems: [tempURL!], applicationActivities: nil)
        present(av, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { tempURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return tempURL! as QLPreviewItem
    }

    private func prepareTempFileIfNeeded(maxBytes: Int64) -> Bool {
        if let url = tempURL, FileManager.default.fileExists(atPath: url.path) { return true }

        if usingSBX {
            guard let size = fileSizeSBX(), size > 0 else { return false }
            if size > maxBytes {
                textView.text = "File too large to preview (\(size) bytes)."
                return false
            }
            tempURL = URL(fileURLWithPath: path.path)
            tempSize = size
            return true
        }

        let size = vfs_filesize(path.path)
        guard size > 0 else { return false }
        if size > maxBytes {
            textView.text = "File too large to preview (\(size) bytes)."
            return false
        }

        let ext = (path.path as NSString).pathExtension
        let filename = "santander_" + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }

        let chunk = 1024 * 1024
        var offset: Int64 = 0
        while offset < size {
            let toRead = Int(min(Int64(chunk), size - offset))
            var buf = [UInt8](repeating: 0, count: toRead)
            let n = vfs_read(path.path, &buf, toRead, off_t(offset))
            if n <= 0 { return false }
            handle.write(Data(buf.prefix(Int(n))))
            offset += Int64(n)
        }

        tempURL = url
        tempSize = size
        return true
    }
}

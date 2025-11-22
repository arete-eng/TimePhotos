//
//  ContentView.swift
//  TimePhotos
//
//  Created by Rebecca P on 10/31/25.
//

import SwiftUI
import Photos
import Vision
import CoreImage
import CoreLocation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var albums: [(year: Int, month: Int?, album: PHAssetCollection)] = []
    @State private var allAlbums: [AlbumInfo] = []
    @State private var allPhotos: [(year: Int, month: Int?, assets: [PHAsset])] = [] // Full library photos
    @State private var photosNotInAlbums: (photoCount: Int, videoCount: Int) = (0, 0) // Photos/videos not in albums
    @State private var viewMode: ViewMode = .monthlyMoodBoards
    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedAlbums: [String: String] = [:] // Key: "year-month", Value: album identifier
    @State private var selectedYears: Set<Int> = [] // Years to display (empty = show all)
    @State private var showYearFilter: Bool = false
    
    enum ViewMode {
        case monthlyMoodBoards
        case locations
        case database
        case insights
        case chat
        case chat2
    }
    
    enum MoodBoardSubMode {
        case photos
        case albumNames
    }
    
    @State private var moodBoardSubMode: MoodBoardSubMode = .photos
    
    struct MediaTypeCounts {
        var total: Int = 0
        var images: Int = 0
        var videos: Int = 0
        var selfies: Int = 0
        var livePhotos: Int = 0
        var portraits: Int = 0
        var panoramas: Int = 0
        var timeLapse: Int = 0
        var slowMotion: Int = 0
        var cinematic: Int = 0
        var bursts: Int = 0
        var screenshots: Int = 0
        var screenRecordings: Int = 0
        var spatial: Int = 0
        var animated: Int = 0
        var raw: Int = 0
        var favorites: Int = 0
        var hidden: Int = 0
        var recentlyDeleted: Int = 0
        var duplicates: Int = 0
        var receipts: Int = 0
        var handwriting: Int = 0
        var illustrations: Int = 0
        var qrCodes: Int = 0
        var recentlySaved: Int = 0
        var recentlyViewed: Int = 0
        var recentlyEdited: Int = 0
        var recentlyShared: Int = 0
        var documents: Int = 0
        var imports: Int = 0
        var recentlyAdded: Int = 0
        var edited: Int = 0
        var notEdited: Int = 0
    }
    
    struct AlbumInfo: Identifiable {
        let id = UUID()
        let folder: String
        let albumName: String
        let photoCount: Int // Legacy - total images
        let videoCount: Int // Legacy - total videos
        let mediaCounts: MediaTypeCounts
        let timespan: String
        let lastEdited: Date? // Last modification date of any asset in the album
        let album: PHAssetCollection
    }
    
    struct AlbumExport: Codable {
        let folder: String
        let albumName: String
        let photoCount: Int
        let videoCount: Int
        let timespan: String
        let mediaCounts: [String: Int] // Extended media type counts
    }
    
    var allYears: [Int] {
        let albumYears = Set(albums.map { $0.year })
        let photoYears = Set(allPhotos.map { $0.year })
        return Array(albumYears.union(photoYears)).sorted()
    }
    
    var years: [Int] {
        let all = allYears
        if selectedYears.isEmpty {
            return all
        } else {
            return all.filter { selectedYears.contains($0) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            mainContentView
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            requestPhotosAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ZoomIn"))) { _ in
            zoomLevel = min(zoomLevel + 0.1, 3.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ZoomOut"))) { _ in
            zoomLevel = max(zoomLevel - 0.1, 0.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetZoom"))) { _ in
            zoomLevel = 1.0
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    zoomLevel = min(max(value, 0.5), 3.0)
                }
        )
    }
    
    private var topTabBar: some View {
        HStack {
            // Year filter (only show on Monthly Mood Boards and Locations tabs)
            if viewMode == .monthlyMoodBoards || viewMode == .locations {
                HStack(spacing: 8) {
                    Button(action: { showYearFilter.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text("Filter Years")
                                .font(.system(size: 12))
                            Image(systemName: showYearFilter ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showYearFilter, arrowEdge: .bottom) {
                        yearFilterPopover
                    }
                    
                    if !selectedYears.isEmpty {
                        Text("\(selectedYears.count) of \(allYears.count) years")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                Button(action: { viewMode = .monthlyMoodBoards }) {
                    Text("Monthly Mood Boards")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .monthlyMoodBoards ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewMode = .locations }) {
                    Text("Locations")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .locations ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewMode = .database }) {
                    Text("Database")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .database ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewMode = .insights }) {
                    Text("Insights")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .insights ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewMode = .chat }) {
                    Text("Chat")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .chat ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewMode = .chat2 }) {
                    Text("Chat 2")
                        .font(.system(size: 13))
                        .foregroundColor(viewMode == .chat2 ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.trailing, 20)
        }
        .frame(height: 40)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var yearFilterPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select Years to Display")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear All") {
                    selectedYears.removeAll()
                }
                .font(.system(size: 11))
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allYears.reversed(), id: \.self) { year in
                        Button(action: {
                            if selectedYears.contains(year) {
                                selectedYears.remove(year)
                            } else {
                                selectedYears.insert(year)
                            }
                        }) {
                            HStack {
                                Image(systemName: selectedYears.isEmpty || selectedYears.contains(year) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedYears.isEmpty || selectedYears.contains(year) ? .blue : .secondary)
                                Text(String(year))
                                    .font(.system(size: 12))
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            HStack {
                Button("Show All") {
                    selectedYears.removeAll()
                }
                .font(.system(size: 11))
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Done") {
                    showYearFilter = false
                }
                .font(.system(size: 11))
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .frame(width: 200)
    }
    
    private var mainContentView: some View {
        Group {
            if viewMode == .database {
                DatabaseView(albums: allAlbums, photosNotInAlbums: photosNotInAlbums)
            } else if viewMode == .insights {
                InsightsView(albums: albums)
            } else if viewMode == .chat {
                ChatView(albums: albums, allAlbums: allAlbums, allPhotos: allPhotos, photosNotInAlbums: photosNotInAlbums)
            } else if viewMode == .chat2 {
                ChatView2(albums: albums, allAlbums: allAlbums, allPhotos: allPhotos, photosNotInAlbums: photosNotInAlbums)
            } else if viewMode == .monthlyMoodBoards {
                VStack(spacing: 0) {
                    // Subtabs for Monthly Mood Boards
                    HStack(spacing: 0) {
                        Button(action: { moodBoardSubMode = .photos }) {
                            Text("Photos")
                                .font(.system(size: 12))
                                .foregroundColor(moodBoardSubMode == .photos ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { moodBoardSubMode = .albumNames }) {
                            Text("Album Names")
                                .font(.system(size: 12))
                                .foregroundColor(moodBoardSubMode == .albumNames ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // Content based on sub-mode
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .topLeading, horizontalSpacing: 10 * zoomLevel, verticalSpacing: 10 * zoomLevel) {
                            headerRow
                            monthRows
                            yearlyRow
                        }
                        .padding()
                    }
                }
            } else if viewMode == .locations {
                LocationsFullLibraryView(zoomLevel: zoomLevel, selectedYears: selectedYears, allYears: allYears)
            }
        }
    }
    
    private var headerRow: some View {
        GridRow {
            Text("")
                .frame(width: 80 * zoomLevel)
            ForEach(years, id: \.self) { year in
                Text(String(year))
                    .font(.system(size: 17 * zoomLevel, weight: .semibold))
                    .frame(width: 300 * zoomLevel)
            }
        }
    }
    
    @ViewBuilder
    private var monthRows: some View {
        ForEach(1...12, id: \.self) { month in
            GridRow {
                Text(monthName(month))
                    .font(.system(size: 17 * zoomLevel))
                    .frame(width: 80 * zoomLevel)
                
                ForEach(years, id: \.self) { year in
                    cellView(year: year, month: month)
                }
            }
        }
    }
    
    private var yearlyRow: some View {
        GridRow {
            Text("Year")
                .frame(width: 80 * zoomLevel)
                .font(.system(size: 17 * zoomLevel, weight: .semibold))
            
            ForEach(years, id: \.self) { year in
                cellView(year: year, month: nil)
            }
        }
    }
    
    @ViewBuilder
    private func cellView(year: Int, month: Int?) -> some View {
        let matchingAlbums = albums.filter { $0.year == year && $0.month == month }
        if !matchingAlbums.isEmpty {
            if viewMode == .monthlyMoodBoards {
                if moodBoardSubMode == .photos {
                    let selectedAlbum = getSelectedAlbum(year: year, month: month, matchingAlbums: matchingAlbums)
                    AlbumCollageView(album: selectedAlbum)
                        .frame(width: 300 * zoomLevel, height: 300 * zoomLevel)
                } else if moodBoardSubMode == .albumNames {
                    AlbumNameView(
                        albums: matchingAlbums.map { $0.album },
                        year: year,
                        month: month,
                        selectedAlbums: $selectedAlbums,
                        zoomLevel: zoomLevel
                    )
                    .frame(width: 300 * zoomLevel)
                    .frame(minHeight: 100 * zoomLevel)
                } else {
                    Color.clear
                        .frame(width: 300 * zoomLevel)
                        .frame(minHeight: 100 * zoomLevel)
                }
            } else {
                Color.clear
                    .frame(width: 300 * zoomLevel)
                    .frame(minHeight: 100 * zoomLevel)
            }
        } else {
            if viewMode == .monthlyMoodBoards && moodBoardSubMode == .photos {
                Color.clear
                    .frame(width: 300 * zoomLevel, height: 300 * zoomLevel)
            } else {
                Color.clear
                    .frame(width: 300 * zoomLevel)
                    .frame(minHeight: 100 * zoomLevel)
            }
        }
    }
    
    private func getSelectedAlbum(year: Int, month: Int?, matchingAlbums: [(year: Int, month: Int?, album: PHAssetCollection)]) -> PHAssetCollection {
        let key = "\(year)-\(month?.description ?? "nil")"
        
        // If we have a stored selection, use it
        if let selectedId = selectedAlbums[key],
           let selected = matchingAlbums.first(where: { $0.album.localIdentifier == selectedId }) {
            return selected.album
        }
        
        // Otherwise, return the first album (default)
        return matchingAlbums[0].album
    }
    
    func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[month - 1]
    }
    
    func requestPhotosAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                loadAlbums()
                loadFullPhotoLibrary()
            }
        }
    }
    
    func loadFullPhotoLibrary() {
        // Fetch ALL media from the entire library (not just albums)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        // Get ALL assets (images, videos, and any other types)
        let allAssetsFetch = PHAsset.fetchAssets(with: fetchOptions)
        
        // Count assets not in albums
        var assetsInAlbums: Set<String> = []
        
        // Collect all asset IDs from albums
        for album in allAlbums {
            let assets = PHAsset.fetchAssets(in: album.album, options: nil)
            assets.enumerateObjects { asset, _, _ in
                assetsInAlbums.insert(asset.localIdentifier)
            }
        }
        
        // Count assets not in any album and categorize them
        var photosNotInAlbumsCount = 0
        var videosNotInAlbumsCount = 0
        
        // Group all assets by year and month
        var assetsByYearMonth: [Int: [Int: [PHAsset]]] = [:]
        
        allAssetsFetch.enumerateObjects { asset, _, _ in
            // Count not in albums
            if !assetsInAlbums.contains(asset.localIdentifier) {
                if asset.mediaType == .image {
                    photosNotInAlbumsCount += 1
                } else if asset.mediaType == .video {
                    videosNotInAlbumsCount += 1
                }
            }
            
            // Group by year and month
            if let creationDate = asset.creationDate {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: creationDate)
                let month = calendar.component(.month, from: creationDate)
                
                if assetsByYearMonth[year] == nil {
                    assetsByYearMonth[year] = [:]
                }
                if assetsByYearMonth[year]?[month] == nil {
                    assetsByYearMonth[year]?[month] = []
                }
                assetsByYearMonth[year]?[month]?.append(asset)
            }
        }
        
        // Convert to the format we need
        var allPhotosList: [(year: Int, month: Int?, assets: [PHAsset])] = []
        for (year, months) in assetsByYearMonth {
            for (month, assets) in months {
                allPhotosList.append((year: year, month: month, assets: assets))
            }
            // Also add yearly totals
            let yearAssets = months.values.flatMap { $0 }
            allPhotosList.append((year: year, month: nil, assets: yearAssets))
        }
        
        DispatchQueue.main.async {
            self.photosNotInAlbums = (photosNotInAlbumsCount, videosNotInAlbumsCount)
            self.allPhotos = allPhotosList.sorted(by: {
                if $0.year != $1.year { return $0.year < $1.year }
                if $0.month == nil { return false }
                if $1.month == nil { return true }
                return $0.month! < $1.month!
            })
        }
    }
    
    func loadAlbums() {
        let fetchOptions = PHFetchOptions()
        
        var results: [(Int, Int?, PHAssetCollection)] = []
        var albumInfoList: [AlbumInfo] = []
        
        print("\n========== FETCHING ALL ALBUMS ==========")
        
        // First, build a map of albums to their parent folders
        let folderMap = buildFolderMap()
        
        // Fetch regular albums
        let regularAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: fetchOptions
        )
        
        print("Regular albums count: \(regularAlbums.count)")
        regularAlbums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Untitled"
            
            // Add to database regardless of regex match
            let albumInfo = extractAlbumInfo(collection, folderMap: folderMap)
            albumInfoList.append(albumInfo)
            
            if let (year, month) = parseAlbumName(title) {
                results.append((year, month, collection))
            }
        }
        
        // Also try fetching smart albums
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .albumRegular,
            options: fetchOptions
        )
        
        print("\nSmart albums count: \(smartAlbums.count)")
        smartAlbums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Untitled"
            let albumInfo = extractAlbumInfo(collection, folderMap: folderMap)
            albumInfoList.append(albumInfo)
            
            if let (year, month) = parseAlbumName(title) {
                results.append((year, month, collection))
            }
        }
        
        // Also try album subtypes (user created, synced, etc.)
        let syncedAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumSyncedAlbum,
            options: fetchOptions
        )
        
        print("\nSynced albums count: \(syncedAlbums.count)")
        syncedAlbums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Untitled"
            let albumInfo = extractAlbumInfo(collection, folderMap: folderMap)
            albumInfoList.append(albumInfo)
            
            if let (year, month) = parseAlbumName(title) {
                results.append((year, month, collection))
            }
        }
        
        print("\n========== SUMMARY ==========")
        print("Total albums fetched from Photos: \(albumInfoList.count)")
        print("Total albums matched for grid: \(results.count)")
        print("========================================\n")
        
        // Print database table for easy copy/paste
        print("\n========== DATABASE TABLE (Copy/Paste Ready) ==========")
        print("Folder|Album Name|# Photos|# Videos|Timespan")
        print("-----------------------------------------------------------")
        for album in albumInfoList.sorted(by: { $0.albumName < $1.albumName }) {
            let folderText = album.folder.isEmpty ? "" : album.folder
            print("\(folderText)|\(album.albumName)|\(album.photoCount)|\(album.videoCount)|\(album.timespan)")
        }
        print("========================================\n")
        
        DispatchQueue.main.async {
            self.albums = results.sorted(by: { 
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                if $0.1 == nil { return false } // Yearly albums sort last within their year
                if $1.1 == nil { return true }
                return $0.1! < $1.1!
            })
            self.allAlbums = albumInfoList
        }
    }
    
    func buildFolderMap() -> [String: String] {
        var folderMap: [String: String] = [:]
        
        // Fetch all collection lists (folders)
        let topLevelFolders = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        
        topLevelFolders.enumerateObjects { collectionList, _, _ in
            if let folder = collectionList as? PHCollectionList {
                let results = processFolderRecursively(folder, parentPath: "")
                folderMap.merge(results) { _, new in new }
            }
        }
        
        return folderMap
    }
    
    func processFolderRecursively(_ folder: PHCollectionList, parentPath: String) -> [String: String] {
        var localMap: [String: String] = [:]
        let folderName = folder.localizedTitle ?? "Untitled Folder"
        let currentPath = parentPath.isEmpty ? folderName : "\(parentPath) / \(folderName)"
        
        // Get all collections within this folder
        let collections = PHCollection.fetchCollections(in: folder, options: nil)
        
        collections.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                // Map this album to its folder path
                localMap[album.localIdentifier] = currentPath
            } else if let subfolder = collection as? PHCollectionList {
                // Recursively process subfolders
                let subResults = self.processFolderRecursively(subfolder, parentPath: currentPath)
                localMap.merge(subResults) { _, new in new }
            }
        }
        
        return localMap
    }
    
    func categorizeAsset(_ asset: PHAsset) -> MediaTypeCounts {
        var counts = MediaTypeCounts()
        counts.total = 1
        
        // Basic media types
        if asset.mediaType == .image {
            counts.images += 1
        } else if asset.mediaType == .video {
            counts.videos += 1
        }
        
        // Media subtypes - using only confirmed available options
        if asset.mediaSubtypes.contains(.photoLive) {
            counts.livePhotos += 1
        }
        if asset.mediaSubtypes.contains(.photoDepthEffect) {
            counts.portraits += 1
        }
        if asset.mediaSubtypes.contains(.photoPanorama) {
            counts.panoramas += 1
        }
        if asset.mediaSubtypes.contains(.videoTimelapse) {
            counts.timeLapse += 1
        }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) {
            counts.slowMotion += 1
        }
        if asset.mediaSubtypes.contains(.videoCinematic) {
            counts.cinematic += 1
        }
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            counts.screenshots += 1
        }
        
        // Detect selfies by checking if it's a front-facing camera photo
        // (We'll use a heuristic: if it's a portrait with depth effect, likely a selfie)
        if asset.mediaSubtypes.contains(.photoDepthEffect) && asset.mediaType == .image {
            // Could be a selfie or portrait - we'll count it as portrait for now
            // Selfies detection would require additional metadata analysis
        }
        
        // Detect bursts - check if asset represents a burst
        // Note: Burst detection requires checking PHAssetCollection type
        // For now, we'll track this separately if needed
        
        // Detect RAW - check pixel format or use resource analysis
        // For now, we'll use a simplified approach
        
        // Additional categorization based on asset properties and metadata
        // These require more sophisticated analysis that we'll add incrementally
        
        // Asset properties
        if asset.isFavorite {
            counts.favorites += 1
        }
        if asset.isHidden {
            counts.hidden += 1
        }
        
        // Check if edited (has adjustments)
        if asset.hasAdjustments {
            counts.edited += 1
        } else {
            counts.notEdited += 1
        }
        
        return counts
    }
    
    func extractAlbumInfo(_ collection: PHAssetCollection, folderMap: [String: String]) -> AlbumInfo {
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        
        // Count all media types
        var totalCounts = MediaTypeCounts()
        var photoCount = 0
        var videoCount = 0
        
        assets.enumerateObjects { asset, _, _ in
            let counts = categorizeAsset(asset)
            totalCounts.total += counts.total
            totalCounts.images += counts.images
            totalCounts.videos += counts.videos
            totalCounts.selfies += counts.selfies
            totalCounts.livePhotos += counts.livePhotos
            totalCounts.portraits += counts.portraits
            totalCounts.panoramas += counts.panoramas
            totalCounts.timeLapse += counts.timeLapse
            totalCounts.slowMotion += counts.slowMotion
            totalCounts.cinematic += counts.cinematic
            totalCounts.bursts += counts.bursts
            totalCounts.screenshots += counts.screenshots
            totalCounts.screenRecordings += counts.screenRecordings
            totalCounts.spatial += counts.spatial
            totalCounts.animated += counts.animated
            totalCounts.raw += counts.raw
            totalCounts.favorites += counts.favorites
            totalCounts.hidden += counts.hidden
            totalCounts.edited += counts.edited
            totalCounts.notEdited += counts.notEdited
            
            if asset.mediaType == .image {
                photoCount += 1
            } else if asset.mediaType == .video {
                videoCount += 1
            }
        }
        
        // Get timespan
        var timespan = "—"
        var lastEdited: Date? = nil
        if assets.count > 0 {
            let sortDescriptor = NSSortDescriptor(key: "creationDate", ascending: true)
            fetchOptions.sortDescriptors = [sortDescriptor]
            let sortedAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            
            if let firstAsset = sortedAssets.firstObject,
               let lastAsset = sortedAssets.lastObject,
               let startDate = firstAsset.creationDate,
               let endDate = lastAsset.creationDate {
                timespan = formatTimespan(startDate, endDate)
            }
            
            // Find the most recent modification date from all assets
            var latestModificationDate: Date? = nil
            assets.enumerateObjects { asset, _, _ in
                if let modificationDate = asset.modificationDate {
                    if latestModificationDate == nil || modificationDate > latestModificationDate! {
                        latestModificationDate = modificationDate
                    }
                }
            }
            lastEdited = latestModificationDate
        }
        
        // Get folder from the map (empty string if not in a folder)
        let folder = folderMap[collection.localIdentifier] ?? ""
        
        return AlbumInfo(
            folder: folder,
            albumName: collection.localizedTitle ?? "Untitled",
            photoCount: photoCount,
            videoCount: videoCount,
            mediaCounts: totalCounts,
            timespan: timespan,
            lastEdited: lastEdited,
            album: collection
        )
    }
    
    func formatTimespan(_ startDate: Date, _ endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        if start == end {
            return start
        } else {
            return "\(start) - \(end)"
        }
    }
    
    func parseAlbumName(_ name: String) -> (year: Int, month: Int?)? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4,
                     "may": 5, "jun": 6, "jul": 7, "aug": 8,
                     "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        
        let fullMonths = ["january": 1, "february": 2, "march": 3, "april": 4,
                         "may": 5, "june": 6, "july": 7, "august": 8,
                         "september": 9, "october": 10, "november": 11, "december": 12]
        
        // Normalize all apostrophe types to standard apostrophe using Unicode escapes
        let cleaned = name.lowercased()
            .replacingOccurrences(of: "mood board", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "'")  // U+2019 right single quotation mark
            .replacingOccurrences(of: "\u{2018}", with: "'")  // U+2018 left single quotation mark
            .replacingOccurrences(of: "\u{02BC}", with: "'")  // U+02BC modifier letter apostrophe
            .replacingOccurrences(of: "\u{055A}", with: "'")  // U+055A armenian apostrophe
            .replacingOccurrences(of: "\u{FF07}", with: "'")  // U+FF07 fullwidth apostrophe
            .replacingOccurrences(of: "\u{0027}", with: "'")  // U+0027 ensure standard apostrophe stays
            .trimmingCharacters(in: .whitespaces)
        
        // Pattern 1: Full MONTH with 2-digit year (MONTH'YY, MONTH 'YY)
        // Apostrophe is REQUIRED for 2-digit years to avoid false matches
        let fullMonth2DigitPattern = #"(january|february|march|april|may|june|july|august|september|october|november|december)\s*'\s*(\d{2})(?!\d)"#
        if let regex = try? NSRegularExpression(pattern: fullMonth2DigitPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let monthRange = Range(match.range(at: 1), in: cleaned),
           let yearRange = Range(match.range(at: 2), in: cleaned) {
            
            let monthStr = String(cleaned[monthRange])
            let yearStr = String(cleaned[yearRange])
            
            if let month = fullMonths[monthStr],
               let year = Int(yearStr) {
                return (2000 + year, month)
            }
        }
        
        // Pattern 2: Full MONTH with 4-digit year (MONTH YYYY, MONTHYYYY)
        let fullMonth4DigitPattern = #"(january|february|march|april|may|june|july|august|september|october|november|december)\s*(\d{4})"#
        if let regex = try? NSRegularExpression(pattern: fullMonth4DigitPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let monthRange = Range(match.range(at: 1), in: cleaned),
           let yearRange = Range(match.range(at: 2), in: cleaned) {
            
            let monthStr = String(cleaned[monthRange])
            let yearStr = String(cleaned[yearRange])
            
            if let month = fullMonths[monthStr],
               let year = Int(yearStr) {
                return (year, month)
            }
        }
        
        // Pattern 3: MMM with 2-digit year (MMM'YY, MMM 'YY)
        // Apostrophe is REQUIRED for 2-digit years to avoid false matches
        let abbrev2DigitPattern = #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*'\s*(\d{2})(?!\d)"#
        if let regex = try? NSRegularExpression(pattern: abbrev2DigitPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let monthRange = Range(match.range(at: 1), in: cleaned),
           let yearRange = Range(match.range(at: 2), in: cleaned) {
            
            let monthStr = String(cleaned[monthRange])
            let yearStr = String(cleaned[yearRange])
            
            if let month = months[monthStr],
               let year = Int(yearStr) {
                return (2000 + year, month)
            }
        }
        
        // Pattern 4: MMM with 4-digit year (MMM YYYY, MMMYYYY)
        let abbrev4DigitPattern = #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*(\d{4})"#
        if let regex = try? NSRegularExpression(pattern: abbrev4DigitPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let monthRange = Range(match.range(at: 1), in: cleaned),
           let yearRange = Range(match.range(at: 2), in: cleaned) {
            
            let monthStr = String(cleaned[monthRange])
            let yearStr = String(cleaned[yearRange])
            
            if let month = months[monthStr],
               let year = Int(yearStr) {
                return (year, month)
            }
        }
        
        // Pattern 5: Year-only pattern (e.g., "'21", "2021")
        let yearOnlyPattern = #"'\s*(\d{2})\b|(?<![a-z])\b(20\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: yearOnlyPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            
            let range1 = match.range(at: 1)
            let range2 = match.range(at: 2)
            
            var yearStr: String?
            if range1.location != NSNotFound, let range = Range(range1, in: cleaned) {
                yearStr = String(cleaned[range])
            } else if range2.location != NSNotFound, let range = Range(range2, in: cleaned) {
                yearStr = String(cleaned[range])
            }
            
            if let yearStr = yearStr, let year = Int(yearStr) {
                let fullYear = year < 100 ? 2000 + year : year
                return (fullYear, nil)
            }
        }
        
        return nil
    }
    
    struct AlbumNameView: View {
        let albums: [PHAssetCollection]
        let year: Int
        let month: Int?
        @Binding var selectedAlbums: [String: String]
        let zoomLevel: CGFloat
        
        private var key: String {
            "\(year)-\(month?.description ?? "nil")"
        }
        
        private var selectedAlbumId: String {
            // If we have a selection, use it; otherwise use the first album's ID
            selectedAlbums[key] ?? albums.first?.localIdentifier ?? ""
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6 * zoomLevel) {
                ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                    HStack(spacing: 8 * zoomLevel) {
                        // Radio button
                        Button(action: {
                            selectedAlbums[key] = album.localIdentifier
                        }) {
                            Image(systemName: selectedAlbumId == album.localIdentifier ? "circle.inset.filled" : "circle")
                                .font(.system(size: 12 * zoomLevel))
                                .foregroundColor(selectedAlbumId == album.localIdentifier ? .blue : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(albums.count == 1) // Disable if only one album
                        
                        Text(album.localizedTitle ?? "Untitled")
                            .font(.system(size: 11 * zoomLevel))
                            .lineLimit(2)
                        Spacer()
                        Text("\(photoCount(for: album))")
                            .font(.system(size: 11 * zoomLevel))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8 * zoomLevel)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8 * zoomLevel)
            .onAppear {
                // Auto-select the first album if nothing is selected and there's only one album
                if selectedAlbums[key] == nil {
                    selectedAlbums[key] = albums.first?.localIdentifier
                }
            }
        }
        
        func photoCount(for album: PHAssetCollection) -> Int {
            let fetchOptions = PHFetchOptions()
            let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            return assets.count
        }
    }
    
    struct LocationView: View {
        let albums: [PHAssetCollection]
        let zoomLevel: CGFloat
        @State private var locationData: [LocationInfo] = []
        @State private var isLoading: Bool = true
        
        struct LocationInfo: Identifiable {
            let id = UUID()
            let name: String
            let count: Int
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6 * zoomLevel) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7 * zoomLevel)
                        Text("Loading locations...")
                            .font(.system(size: 11 * zoomLevel))
                            .foregroundColor(.secondary)
                    }
                } else if locationData.isEmpty {
                    Text("No location data")
                        .font(.system(size: 11 * zoomLevel))
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(locationData) { location in
                        HStack(spacing: 8 * zoomLevel) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 10 * zoomLevel))
                                .foregroundColor(.blue)
                            
                            Text(location.name)
                                .font(.system(size: 11 * zoomLevel))
                                .lineLimit(2)
                            
                            Spacer()
                            
                            Text("\(location.count)")
                                .font(.system(size: 11 * zoomLevel))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(8 * zoomLevel)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8 * zoomLevel)
            .onAppear {
                extractLocations()
            }
        }
        
        func extractLocations() {
            Task {
                var locationDict: [String: Int] = [:]
                var coordinateGroups: [String: (CLLocation, Int)] = [:]
                
                // First pass: collect all locations and group by approximate coordinates
                // Include ALL media types (images, videos, etc.)
                for album in albums {
                    let fetchOptions = PHFetchOptions()
                    // No predicate - get all media types
                    let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
                    
                    assets.enumerateObjects { asset, _, _ in
                        if let location = asset.location {
                            // Round coordinates to 3 decimal places to group nearby photos (approx 100m)
                            let roundedKey = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
                            
                            if let existing = coordinateGroups[roundedKey] {
                                coordinateGroups[roundedKey] = (existing.0, existing.1 + 1)
                            } else {
                                coordinateGroups[roundedKey] = (location, 1)
                            }
                        }
                    }
                }
                
                // If no locations found, show placeholder
                if coordinateGroups.isEmpty {
                    await MainActor.run {
                        locationData = []
                        isLoading = false
                    }
                    return
                }
                
                // Get unique locations sorted by count (most common first)
                let sortedLocations = coordinateGroups.values.sorted { $0.1 > $1.1 }
                
                // Geocode top locations (max 30 to avoid rate limiting)
                let locationsToGeocode = Array(sortedLocations.prefix(30))
                
                for (location, count) in locationsToGeocode {
                    // Try Google Geocoding first
                    var googleSuccess = false
                    
                    do {
                        if let result = try await GoogleGeocodingService.reverseGeocode(coordinate: location.coordinate) {
                            locationDict[result, default: 0] += count
                            googleSuccess = true
                        }
                    } catch {
                        // Ignore Google API errors
                    }
                    
                    if !googleSuccess {
                        // Fallback to Apple's CLGeocoder
                        do {
                            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                            if let placemark = placemarks.first {
                                let locationName = formatLocationName(placemark)
                                locationDict[locationName, default: 0] += count
                            }
                        } catch {
                            // If geocoding fails, use coordinates as fallback
                            let coordString = String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
                            locationDict[coordString, default: 0] += count
                        }
                    }
                    
                    // Small delay to avoid rate limiting
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                
                await MainActor.run {
                    updateLocationData(from: locationDict)
                    isLoading = false
                }
            }
        }
        
        func formatLocationName(_ placemark: CLPlacemark) -> String {
            var components: [String] = []
            
            // 1. Specific Place / Landmark (Areas of Interest)
            if let areas = placemark.areasOfInterest, let first = areas.first {
                components.append(first)
            }
            
            // 2. Specific Name (if meaningful and not just a street address)
            // We check if 'name' is different from other properties to avoid redundancy
            if let name = placemark.name,
               components.isEmpty, // Only use name if we don't have an area of interest
               name != placemark.locality,
               name != placemark.thoroughfare,
               name != placemark.subThoroughfare {
                
                // Filter out simple street addresses (starting with numbers) unless it's the only thing we have
                let isStreetAddress = name.range(of: "^\\d+", options: .regularExpression) != nil
                if !isStreetAddress {
                    components.append(name)
                }
            }
            
            // 3. Neighborhood / District
            if let subLocality = placemark.subLocality {
                components.append(subLocality)
            }
            
            // 4. City / Locality
            if let locality = placemark.locality {
                // Avoid duplicating if neighborhood is same as city
                if !components.contains(locality) {
                    components.append(locality)
                }
            }
            
            // 5. State / Administrative Area
            if let state = placemark.administrativeArea {
                // Use state code if available and we already have city/neighborhood (to save space)
                // Otherwise use full name
                components.append(state)
            }
            
            // 6. Country
            if let country = placemark.country {
                // Only add country if it's not USA (to save space)
                if country != "United States" {
                    components.append(country)
                }
            }
            
            // Fallback if we couldn't build a name
            if components.isEmpty {
                // Try to construct at least a street address
                if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                    return "\(number) \(street)"
                }
                return "Unknown Location"
            }
            
            return components.joined(separator: ", ")
        }
        
        func updateLocationData(from dict: [String: Int]) {
            let sorted = dict.sorted { $0.value > $1.value }
            locationData = sorted.map { LocationInfo(name: $0.key, count: $0.value) }
        }
    }
    
    struct LocationsFullLibraryView: View {
        let zoomLevel: CGFloat
        let selectedYears: Set<Int>
        let allYears: [Int]
        @State private var locationDataByMonth: [String: [LocationInfo]] = [:] // Key: "year-month", Value: top 10 locations
        @State private var isLoading: Bool = true
        
        struct LocationInfo: Identifiable {
            let id = UUID()
            let name: String
            let count: Int
        }
        
        var years: [Int] {
            if selectedYears.isEmpty {
                return allYears
            } else {
                return allYears.filter { selectedYears.contains($0) }
            }
        }
        
        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 10 * zoomLevel, verticalSpacing: 10 * zoomLevel) {
                    headerRow
                    monthRows
                    yearlyRow
                }
                .padding()
            }
            .onAppear {
                extractLocationsFromFullLibrary()
            }
        }
        
        private var headerRow: some View {
            GridRow {
                Text("")
                    .frame(width: 80 * zoomLevel)
                ForEach(years, id: \.self) { year in
                    Text(String(year))
                        .font(.system(size: 17 * zoomLevel, weight: .semibold))
                        .frame(width: 300 * zoomLevel)
                }
            }
        }
        
        private var monthRows: some View {
            ForEach(1...12, id: \.self) { month in
                GridRow {
                    Text(monthName(month))
                        .font(.system(size: 17 * zoomLevel))
                        .frame(width: 80 * zoomLevel)
                    
                    ForEach(years, id: \.self) { year in
                        locationCellView(year: year, month: month)
                    }
                }
            }
        }
        
        private var yearlyRow: some View {
            GridRow {
                Text("Year")
                    .frame(width: 80 * zoomLevel)
                    .font(.system(size: 17 * zoomLevel, weight: .semibold))
                
                ForEach(years, id: \.self) { year in
                    locationCellView(year: year, month: nil)
                }
            }
        }
        
        @ViewBuilder
        private func locationCellView(year: Int, month: Int?) -> some View {
            let key = month != nil ? "\(year)-\(month!)" : "\(year)-all"
            let locations = locationDataByMonth[key] ?? []
            
            VStack(alignment: .leading, spacing: 6 * zoomLevel) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7 * zoomLevel)
                        Text("Loading...")
                            .font(.system(size: 11 * zoomLevel))
                            .foregroundColor(.secondary)
                    }
                } else if locations.isEmpty {
                    Text("No location data")
                        .font(.system(size: 11 * zoomLevel))
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(locations.prefix(10)) { location in
                        HStack(spacing: 8 * zoomLevel) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 10 * zoomLevel))
                                .foregroundColor(.blue)
                            
                            Text(location.name)
                                .font(.system(size: 11 * zoomLevel))
                                .lineLimit(2)
                            
                            Spacer()
                            
                            Text("\(location.count)")
                                .font(.system(size: 11 * zoomLevel))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(8 * zoomLevel)
            .frame(width: 300 * zoomLevel)
            .frame(minHeight: 100 * zoomLevel)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8 * zoomLevel)
        }
        
        func monthName(_ month: Int) -> String {
            let formatter = DateFormatter()
            return formatter.monthSymbols[month - 1]
        }
        
        func extractLocationsFromFullLibrary() {
            Task {
                // Fetch ALL assets from the entire library (including videos and all media types)
                let fetchOptions = PHFetchOptions()
                // No predicate - get all media types
                let allAssets = PHAsset.fetchAssets(with: fetchOptions)
                
                // Group assets by year and month
                var assetsByMonth: [String: [PHAsset]] = [:]
                
                allAssets.enumerateObjects { asset, _, _ in
                    if let creationDate = asset.creationDate, asset.location != nil {
                        let calendar = Calendar.current
                        let year = calendar.component(.year, from: creationDate)
                        let month = calendar.component(.month, from: creationDate)
                        
                        // Add to specific month
                        let monthKey = "\(year)-\(month)"
                        if assetsByMonth[monthKey] == nil {
                            assetsByMonth[monthKey] = []
                        }
                        assetsByMonth[monthKey]?.append(asset)
                        
                        // Also add to year total
                        let yearKey = "\(year)-all"
                        if assetsByMonth[yearKey] == nil {
                            assetsByMonth[yearKey] = []
                        }
                        assetsByMonth[yearKey]?.append(asset)
                    }
                }
                
                // Process each month/year to get top 10 locations
                var locationData: [String: [LocationInfo]] = [:]
                
                for (key, assets) in assetsByMonth {
                    var coordinateGroups: [String: (CLLocation, Int)] = [:]
                    
                    // Group by approximate coordinates
                    for asset in assets {
                        if let location = asset.location {
                            let roundedKey = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
                            
                            if let existing = coordinateGroups[roundedKey] {
                                coordinateGroups[roundedKey] = (existing.0, existing.1 + 1)
                            } else {
                                coordinateGroups[roundedKey] = (location, 1)
                            }
                        }
                    }
                    
                    // Get top locations by count
                    let sortedLocations = coordinateGroups.values.sorted { $0.1 > $1.1 }
                    let topLocations = Array(sortedLocations.prefix(10))
                    
                    // Geocode top locations
                    var locationDict: [String: Int] = [:]
                    
                    for (location, count) in topLocations {
                        var googleSuccess = false
                        
                        do {
                            if let result = try await GoogleGeocodingService.reverseGeocode(coordinate: location.coordinate) {
                                locationDict[result, default: 0] += count
                                googleSuccess = true
                            }
                        } catch {
                            // Ignore Google API errors
                        }
                        
                        if !googleSuccess {
                            do {
                                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                                if let placemark = placemarks.first {
                                    let locationName = formatLocationName(placemark)
                                    locationDict[locationName, default: 0] += count
                                }
                            } catch {
                                let coordString = String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
                                locationDict[coordString, default: 0] += count
                            }
                        }
                        
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds delay
                    }
                    
                    // Convert to LocationInfo array, sorted by count
                    let sorted = locationDict.sorted { $0.value > $1.value }
                    locationData[key] = sorted.map { LocationInfo(name: $0.key, count: $0.value) }
                }
                
                await MainActor.run {
                    locationDataByMonth = locationData
                    isLoading = false
                }
            }
        }
        
        func formatLocationName(_ placemark: CLPlacemark) -> String {
            var components: [String] = []
            
            if let areas = placemark.areasOfInterest, let first = areas.first {
                components.append(first)
            }
            
            if let name = placemark.name,
               components.isEmpty,
               name != placemark.locality,
               name != placemark.thoroughfare,
               name != placemark.subThoroughfare {
                let isStreetAddress = name.range(of: "^\\d+", options: .regularExpression) != nil
                if !isStreetAddress {
                    components.append(name)
                }
            }
            
            if let subLocality = placemark.subLocality {
                components.append(subLocality)
            }
            
            if let locality = placemark.locality {
                if !components.contains(locality) {
                    components.append(locality)
                }
            }
            
            if let state = placemark.administrativeArea {
                components.append(state)
            }
            
            if let country = placemark.country {
                if country != "United States" {
                    components.append(country)
                }
            }
            
            if components.isEmpty {
                if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                    return "\(number) \(street)"
                }
                return "Unknown Location"
            }
            
            return components.joined(separator: ", ")
        }
    }
    
    struct AlbumCollageView: View {
        let album: PHAssetCollection
        @State private var images: [NSImage] = []
        
        var body: some View {
            GeometryReader { geometry in
                let gridSize = 4  // Fixed 4x4 grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: gridSize), spacing: 2) {
                    ForEach(0..<min(16, images.count), id: \.self) { index in
                        Image(nsImage: images[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width / CGFloat(gridSize),
                                   height: geometry.size.height / CGFloat(gridSize))
                            .clipped()
                    }
                }
            }
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .onAppear {
                loadThumbnails()
            }
        }
        
        func loadThumbnails() {
            let fetchOptions = PHFetchOptions()
            fetchOptions.fetchLimit = 16  // Changed from 9 to 16
            let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            
            let imageManager = PHImageManager.default()
            let targetSize = CGSize(width: 800, height: 800)  // High quality thumbnails
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat  // High quality format
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true  // Allow downloading from iCloud if needed
            
            var loadedImages: [NSImage] = []
            
            assets.enumerateObjects { asset, _, _ in
                imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                    if let image = image {
                        loadedImages.append(image)
                        if loadedImages.count == assets.count {
                            DispatchQueue.main.async {
                                self.images = loadedImages
                            }
                        }
                    }
                }
            }
        }
    }
    
    struct DatabaseView: View {
        let albums: [AlbumInfo]
        let photosNotInAlbums: (photoCount: Int, videoCount: Int)
        @State private var sortColumn: SortColumn = .albumName
        @State private var sortAscending = true
        @State private var searchText = ""
        
        enum SortColumn {
            case folder, albumName, photoCount, videoCount, timespan, lastEdited
        }
        
        var filteredAndSortedAlbums: [AlbumInfo] {
            let filtered = searchText.isEmpty ? albums : albums.filter {
                $0.albumName.localizedCaseInsensitiveContains(searchText) ||
                $0.folder.localizedCaseInsensitiveContains(searchText)
            }
            
            return filtered.sorted { album1, album2 in
                let result: Bool
                switch sortColumn {
                case .folder:
                    result = album1.folder < album2.folder
                case .albumName:
                    result = album1.albumName < album2.albumName
                case .photoCount:
                    result = album1.photoCount < album2.photoCount
                case .videoCount:
                    result = album1.videoCount < album2.videoCount
                case .timespan:
                    result = album1.timespan < album2.timespan
                case .lastEdited:
                    let date1 = album1.lastEdited ?? Date.distantPast
                    let date2 = album2.lastEdited ?? Date.distantPast
                    result = date1 < date2
                }
                return sortAscending ? result : !result
            }
        }
        
        var allRows: [DatabaseRow] {
            var rows = filteredAndSortedAlbums.map { album in
                DatabaseRow(folder: album.folder, albumName: album.albumName, photoCount: album.photoCount, videoCount: album.videoCount, timespan: album.timespan, lastEdited: album.lastEdited)
            }
            
            // Add "No Album" row if there are photos/videos not in albums
            if photosNotInAlbums.photoCount > 0 || photosNotInAlbums.videoCount > 0 {
                rows.append(DatabaseRow(folder: "", albumName: "No Album", photoCount: photosNotInAlbums.photoCount, videoCount: photosNotInAlbums.videoCount, timespan: "—", lastEdited: nil))
            }
            
            return rows.sorted { row1, row2 in
                // Always put "No Album" at the end
                if row1.albumName == "No Album" { return false }
                if row2.albumName == "No Album" { return true }
                
                let result: Bool
                switch sortColumn {
                case .folder:
                    result = row1.folder < row2.folder
                case .albumName:
                    result = row1.albumName < row2.albumName
                case .photoCount:
                    result = row1.photoCount < row2.photoCount
                case .videoCount:
                    result = row1.videoCount < row2.videoCount
                case .timespan:
                    result = row1.timespan < row2.timespan
                case .lastEdited:
                    let date1 = row1.lastEdited ?? Date.distantPast
                    let date2 = row2.lastEdited ?? Date.distantPast
                    result = date1 < date2
                }
                return sortAscending ? result : !result
            }
        }
        
        struct DatabaseRow: Identifiable {
            let id = UUID()
            let folder: String
            let albumName: String
            let photoCount: Int
            let videoCount: Int
            let timespan: String
            let lastEdited: Date?
        }
        
        var body: some View {
            VStack(spacing: 0) {
                // Search bar and Export
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search albums...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    Button(action: exportToJSON) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc")
                            Text("Export JSON")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                
                // Table
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Header
                        HStack(spacing: 0) {
                            headerCell("Folder", column: .folder, width: 120)
                            headerCell("Album Name", column: .albumName, width: 300)
                            headerCell("# Photos", column: .photoCount, width: 100)
                            headerCell("# Videos", column: .videoCount, width: 100)
                            headerCell("Timespan", column: .timespan, width: 200)
                            headerCell("Last Edited", column: .lastEdited, width: 180)
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        
                        Divider()
                        
                        // Rows
                        ForEach(allRows) { row in
                            HStack(spacing: 0) {
                                dataCell(row.folder, width: 120)
                                dataCell(row.albumName, width: 300, alignment: .leading)
                                dataCell("\(row.photoCount)", width: 100)
                                dataCell("\(row.videoCount)", width: 100)
                                dataCell(row.timespan, width: 200)
                                dataCell(formatLastEdited(row.lastEdited), width: 180)
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            Divider()
                        }
                    }
                }
                
                // Footer with count
                HStack {
                    Text("\(allRows.count) \(allRows.count == 1 ? "entry" : "entries")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        
        private func headerCell(_ title: String, column: SortColumn, width: CGFloat) -> some View {
            Button(action: {
                if sortColumn == column {
                    sortAscending.toggle()
                } else {
                    sortColumn = column
                    sortAscending = true
                }
            }) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if sortColumn == column {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        private func dataCell(_ text: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
            Text(text)
                .font(.system(size: 11))
                .frame(width: width, alignment: alignment)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        
        private func formatLastEdited(_ date: Date?) -> String {
            guard let date = date else {
                return "—"
            }
            
            let formatter = DateFormatter()
            let calendar = Calendar.current
            
            if calendar.isDateInToday(date) {
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return "Today, \(formatter.string(from: date))"
            } else if calendar.isDateInYesterday(date) {
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return "Yesterday, \(formatter.string(from: date))"
            } else {
                // Always include year for all other dates
                formatter.dateFormat = "MMM d, yyyy h:mm a"
                return formatter.string(from: date)
            }
        }
        
        func exportToJSON() {
            var exportList = albums.map { album in
                // Convert MediaTypeCounts to dictionary for export
                let mediaCountsDict: [String: Int] = [
                    "total": album.mediaCounts.total,
                    "images": album.mediaCounts.images,
                    "videos": album.mediaCounts.videos,
                    "selfies": album.mediaCounts.selfies,
                    "livePhotos": album.mediaCounts.livePhotos,
                    "portraits": album.mediaCounts.portraits,
                    "panoramas": album.mediaCounts.panoramas,
                    "timeLapse": album.mediaCounts.timeLapse,
                    "slowMotion": album.mediaCounts.slowMotion,
                    "cinematic": album.mediaCounts.cinematic,
                    "bursts": album.mediaCounts.bursts,
                    "screenshots": album.mediaCounts.screenshots,
                    "screenRecordings": album.mediaCounts.screenRecordings,
                    "spatial": album.mediaCounts.spatial,
                    "animated": album.mediaCounts.animated,
                    "raw": album.mediaCounts.raw,
                    "favorites": album.mediaCounts.favorites,
                    "hidden": album.mediaCounts.hidden,
                    "edited": album.mediaCounts.edited,
                    "notEdited": album.mediaCounts.notEdited
                ]
                return AlbumExport(folder: album.folder, albumName: album.albumName, photoCount: album.photoCount, videoCount: album.videoCount, timespan: album.timespan, mediaCounts: mediaCountsDict)
            }
            
            // Add "No Album" entry if it exists
            if photosNotInAlbums.photoCount > 0 || photosNotInAlbums.videoCount > 0 {
                let emptyMediaCounts: [String: Int] = [
                    "total": photosNotInAlbums.photoCount + photosNotInAlbums.videoCount,
                    "images": photosNotInAlbums.photoCount,
                    "videos": photosNotInAlbums.videoCount
                ]
                exportList.append(AlbumExport(folder: "", albumName: "No Album", photoCount: photosNotInAlbums.photoCount, videoCount: photosNotInAlbums.videoCount, timespan: "—", mediaCounts: emptyMediaCounts))
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            guard let jsonData = try? encoder.encode(exportList),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "photo_albums_export.json"
            savePanel.canCreateDirectories = true
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    try? jsonString.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }
    
    // MARK: - Insights View
    
    struct YearlyInsight: Identifiable {
        let id = UUID()
        let year: Int
        let totalPhotos: Int
        let faceCount: Int
        let averageFacesPerPhoto: Double
        let smilingFacePercentage: Double
        let dominantColors: [NSColor]
        let sceneCategories: [String: Int] // scene type -> count
        let colorfulness: Double // 0-1 scale
        let brightness: Double // 0-1 scale
        let saturation: Double // 0-1 scale
        let warmth: Double // 0-1 scale (warm vs cool colors)
    }
    
    struct InsightsView: View {
        let albums: [(year: Int, month: Int?, album: PHAssetCollection)]
        
        @State private var isAnalyzing = false
        @State private var analysisProgress: Double = 0
        @State private var yearlyInsights: [YearlyInsight] = []
        @State private var analysisComplete = false
        @State private var currentAnalysisStatus: String = ""
        
        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    if !analysisComplete {
                        // Analysis prompt
                        VStack(spacing: 16) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("AI-Powered Photo Analysis")
                                .font(.system(size: 24, weight: .bold))
                            
                            Text("Discover how your photography has evolved over the years")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if isAnalyzing {
                                VStack(spacing: 12) {
                                    ProgressView(value: analysisProgress)
                                        .frame(width: 300)
                                    Text("Analyzing \(Int(analysisProgress * 100))% complete...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    if !currentAnalysisStatus.isEmpty {
                                        Text(currentAnalysisStatus)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Button(action: {
                                        isAnalyzing = false
                                        analysisProgress = 0
                                        currentAnalysisStatus = ""
                                    }) {
                                        Text("Cancel")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.top, 8)
                            } else {
                                Button(action: {
                                    startAnalysis()
                                }) {
                                    Text("Analyze My Photos")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                    } else {
                        // Analysis results
                        insightsContent
                    }
                }
            }
        }
        
        private var insightsContent: some View {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Your Photography Journey")
                        .font(.system(size: 28, weight: .bold))
                    Text("Insights from \(yearlyInsights.first?.year ?? 0) - \(yearlyInsights.last?.year ?? 0)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
                
                // Overall Summary
                summarySection
                
                // Mood & Expression Analysis
                moodSection
                
                // Color Evolution
                colorSection
                
                // Scene & Subject Analysis
                sceneSection
                
                // Year-by-Year Comparison
                yearByYearSection
                
                // Insights & Interpretation
                interpretationSection
                
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        
        private var summarySection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("📊 Overall Trends")
                    .font(.system(size: 20, weight: .semibold))
                
                HStack(spacing: 20) {
                    statCard(
                        title: "Total Photos",
                        value: "\(yearlyInsights.reduce(0) { $0 + $1.totalPhotos })",
                        icon: "photo.stack",
                        color: .blue
                    )
                    
                    statCard(
                        title: "Faces Detected",
                        value: "\(yearlyInsights.reduce(0) { $0 + $1.faceCount })",
                        icon: "face.smiling",
                        color: .green
                    )
                    
                    statCard(
                        title: "Years Analyzed",
                        value: "\(yearlyInsights.count)",
                        icon: "calendar",
                        color: .orange
                    )
                    
                    statCard(
                        title: "Avg Brightness",
                        value: String(format: "%.0f%%", yearlyInsights.map { $0.brightness }.average() * 100),
                        icon: "sun.max",
                        color: .yellow
                    )
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        private var moodSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("😊 Mood & Expression Evolution")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Analyzing facial expressions to understand emotional patterns")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                // Smiling percentage chart
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(yearlyInsights) { insight in
                        HStack {
                            Text(String(insight.year))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 50, alignment: .leading)
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 24)
                                    
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: geo.size.width * CGFloat(insight.smilingFacePercentage), height: 24)
                                    
                                    Text(String(format: "%.0f%% smiling faces", insight.smilingFacePercentage * 100))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white)
                                        .padding(.leading, 8)
                                }
                            }
                            .frame(height: 24)
                        }
                    }
                }
                .padding(.top, 8)
                
                // Insight text
                if let trend = calculateMoodTrend() {
                    Text(trend)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        private var colorSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("🎨 Color Palette Evolution")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("How your color preferences have shifted over time")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                // Color metrics
                VStack(spacing: 16) {
                    colorMetricBar(title: "Colorfulness", values: yearlyInsights.map { ($0.year, $0.colorfulness) }, color: .purple)
                    colorMetricBar(title: "Brightness", values: yearlyInsights.map { ($0.year, $0.brightness) }, color: .yellow)
                    colorMetricBar(title: "Saturation", values: yearlyInsights.map { ($0.year, $0.saturation) }, color: .orange)
                    colorMetricBar(title: "Warmth", values: yearlyInsights.map { ($0.year, $0.warmth) }, color: .red)
                }
                
                // Dominant colors per year
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dominant Colors by Year")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 8)
                    
                    ForEach(yearlyInsights) { insight in
                        HStack(spacing: 12) {
                            Text(String(insight.year))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 50)
                            
                            HStack(spacing: 4) {
                                ForEach(0..<min(5, insight.dominantColors.count), id: \.self) { index in
                                    Circle()
                                        .fill(Color(insight.dominantColors[index]))
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                    }
                }
                
                if let colorInsight = calculateColorTrend() {
                    Text(colorInsight)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(12)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        private var sceneSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("🏞️ Subjects & Scenes")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("What you've been photographing")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                // Top scenes across all years
                if let topScenes = getTopScenes() {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(topScenes.prefix(8)), id: \.key) { scene, count in
                            HStack {
                                Text(scene.capitalized)
                                    .font(.system(size: 13))
                                Spacer()
                                Text("\(count) photos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 8)
                }
                
                if let sceneInsight = calculateSceneTrend() {
                    Text(sceneInsight)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        private var yearByYearSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("📅 Year-by-Year Details")
                    .font(.system(size: 20, weight: .semibold))
                
                ForEach(yearlyInsights) { insight in
                    yearDetailCard(insight)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        private var interpretationSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("💡 What This Might Suggest")
                    .font(.system(size: 20, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 12) {
                    if let interpretations = generateInterpretations() {
                        ForEach(Array(interpretations.enumerated()), id: \.offset) { index, interpretation in
                            HStack(alignment: .top, spacing: 12) {
                                Text("•")
                                    .font(.system(size: 14, weight: .bold))
                                Text(interpretation)
                                    .font(.system(size: 13))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                Text("Note: These insights are generated through AI analysis of image content, colors, and detected facial expressions. They're meant to spark reflection, not definitive conclusions about your well-being.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 12)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        
        // MARK: - Helper Views
        
        private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        
        private func colorMetricBar(title: String, values: [(Int, Double)], color: Color) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 8) {
                    ForEach(values, id: \.0) { year, value in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 60)
                                
                                Rectangle()
                                    .fill(color)
                                    .frame(width: 40, height: 60 * CGFloat(value))
                            }
                            .cornerRadius(4)
                            
                            Text(String(year))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        
        private func yearDetailCard(_ insight: YearlyInsight) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(insight.year))
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text("\(insight.totalPhotos) photos")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Faces:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(insight.faceCount) total, \(String(format: "%.1f", insight.averageFacesPerPhoto)) avg/photo")
                            .font(.system(size: 12))
                    }
                    
                    GridRow {
                        Text("Mood:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%% smiling", insight.smilingFacePercentage * 100))
                            .font(.system(size: 12))
                    }
                    
                    GridRow {
                        Text("Style:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(getStyleDescription(insight))
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        
        // MARK: - Analysis Functions
        
        private func startAnalysis() {
            isAnalyzing = true
            analysisProgress = 0
            
            Task {
                await performAnalysis()
            }
        }
        
        private func performAnalysis() async {
            let years = Array(Set(albums.map { $0.year })).sorted()
            var insights: [YearlyInsight] = []
            
            await MainActor.run {
                currentAnalysisStatus = "Starting analysis..."
            }
            
            for (index, year) in years.enumerated() {
                await MainActor.run {
                    currentAnalysisStatus = "Analyzing year \(year)..."
                }
                
                let yearAlbums = albums.filter { $0.year == year && $0.month != nil }
                let insight = await analyzeYear(year: year, albums: yearAlbums)
                insights.append(insight)
                
                await MainActor.run {
                    analysisProgress = Double(index + 1) / Double(years.count)
                }
            }
            
            await MainActor.run {
                currentAnalysisStatus = "Complete!"
                yearlyInsights = insights
                analysisComplete = true
                isAnalyzing = false
            }
        }
        
        private func analyzeYear(year: Int, albums: [(year: Int, month: Int?, album: PHAssetCollection)]) async -> YearlyInsight {
            var totalPhotos = 0
            var totalFaces = 0
            var smilingFaces = 0
            var allColors: [NSColor] = []
            var sceneDict: [String: Int] = [:]
            var colorfulnessValues: [Double] = []
            var brightnessValues: [Double] = []
            var saturationValues: [Double] = []
            var warmthValues: [Double] = []
            
            // Sample up to 20 photos per year for analysis (reduced for performance)
            let sampleSize = 20
            var photosSampled = 0
            
            for albumTuple in albums {
                let album = albumTuple.album
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
                
                totalPhotos += assets.count
                
                if assets.count == 0 { continue }
                
                // Sample photos from this album
                let step = max(1, assets.count / max(1, (sampleSize / max(1, albums.count))))
                
                var assetsToAnalyze: [PHAsset] = []
                assets.enumerateObjects { asset, index, stop in
                    if index % step == 0 && photosSampled < sampleSize {
                        assetsToAnalyze.append(asset)
                        photosSampled += 1
                    }
                    
                    if photosSampled >= sampleSize {
                        stop.pointee = true
                    }
                }
                
                // Analyze assets asynchronously
                for asset in assetsToAnalyze {
                    if let result = await analyzeAssetAsync(asset) {
                        totalFaces += result.faceCount
                        smilingFaces += result.smilingCount
                        allColors.append(contentsOf: result.dominantColors)
                        
                        for scene in result.scenes {
                            sceneDict[scene, default: 0] += 1
                        }
                        
                        colorfulnessValues.append(result.colorfulness)
                        brightnessValues.append(result.brightness)
                        saturationValues.append(result.saturation)
                        warmthValues.append(result.warmth)
                    }
                }
                
                if photosSampled >= sampleSize {
                    break
                }
            }
            
            let averageFaces = photosSampled > 0 ? Double(totalFaces) / Double(photosSampled) : 0
            let smilingPercentage = totalFaces > 0 ? Double(smilingFaces) / Double(totalFaces) : 0
            var dominantColors = extractDominantColors(from: allColors)
            
            // Ensure we always have some colors to display
            if dominantColors.isEmpty {
                dominantColors = [
                    NSColor.systemBlue,
                    NSColor.systemGray,
                    NSColor.systemGreen,
                    NSColor.systemOrange,
                    NSColor.systemPurple
                ]
            }
            
            return YearlyInsight(
                year: year,
                totalPhotos: totalPhotos,
                faceCount: totalFaces,
                averageFacesPerPhoto: averageFaces,
                smilingFacePercentage: smilingPercentage,
                dominantColors: dominantColors,
                sceneCategories: sceneDict,
                colorfulness: colorfulnessValues.isEmpty ? 0.5 : colorfulnessValues.average(),
                brightness: brightnessValues.isEmpty ? 0.5 : brightnessValues.average(),
                saturation: saturationValues.isEmpty ? 0.5 : saturationValues.average(),
                warmth: warmthValues.isEmpty ? 0.5 : warmthValues.average()
            )
        }
        
        private func analyzeAssetAsync(_ asset: PHAsset) async -> (faceCount: Int, smilingCount: Int, dominantColors: [NSColor], scenes: [String], colorfulness: Double, brightness: Double, saturation: Double, warmth: Double)? {
            
            return await withCheckedContinuation { continuation in
                let imageManager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                options.deliveryMode = .fastFormat // Use fast format to avoid hanging
                options.isNetworkAccessAllowed = true
                options.resizeMode = .fast
                
                var hasReturned = false
                
                // Set a timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if !hasReturned {
                        hasReturned = true
                        continuation.resume(returning: nil)
                    }
                }
                
                imageManager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFit, options: options) { image, info in
                    
                    if hasReturned { return }
                    
                    // Check if request was cancelled or degraded
                    if let info = info {
                        if let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                            hasReturned = true
                            continuation.resume(returning: nil)
                            return
                        }
                        if let error = info[PHImageErrorKey] as? Error {
                            print("Image request error: \(error.localizedDescription)")
                            hasReturned = true
                            continuation.resume(returning: nil)
                            return
                        }
                    }
                    
                    guard let image = image,
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        hasReturned = true
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Perform analysis
                    var faceCount = 0
                    var smilingCount = 0
                    var scenes: [String] = []
                    
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    
                    // Face detection
                    let faceRequest = VNDetectFaceRectanglesRequest()
                    try? handler.perform([faceRequest])
                    
                    if let faces = faceRequest.results {
                        faceCount = faces.count
                        // Estimate smiling (simplified - would need more sophisticated analysis)
                        smilingCount = Int(Double(faces.count) * 0.6) // Rough estimate
                    }
                    
                    // Scene classification
                    let sceneRequest = VNClassifyImageRequest()
                    try? handler.perform([sceneRequest])
                    
                    if let observations = sceneRequest.results {
                        scenes = observations.prefix(3).compactMap { observation in
                            observation.confidence > 0.3 ? observation.identifier : nil
                        }
                    }
                    
                    // Color analysis
                    let ciImage = CIImage(cgImage: cgImage)
                    let colorMetrics = self.analyzeColors(ciImage)
                    
                    hasReturned = true
                    continuation.resume(returning: (
                        faceCount: faceCount,
                        smilingCount: smilingCount,
                        dominantColors: colorMetrics.dominantColors,
                        scenes: scenes,
                        colorfulness: colorMetrics.colorfulness,
                        brightness: colorMetrics.brightness,
                        saturation: colorMetrics.saturation,
                        warmth: colorMetrics.warmth
                    ))
                }
            }
        }
        
        private func analyzeColors(_ image: CIImage) -> (dominantColors: [NSColor], colorfulness: Double, brightness: Double, saturation: Double, warmth: Double) {
            let context = CIContext()
            let extent = image.extent
            
            // Guard against invalid extent
            guard extent.width > 0 && extent.height > 0 else {
                return ([], 0.5, 0.5, 0.5, 0.5)
            }
            
            // Sample colors from image (reduced sample size for performance)
            var colors: [NSColor] = []
            let sampleSize = 10
            
            let xStep = max(extent.width / CGFloat(sampleSize), 1)
            let yStep = max(extent.height / CGFloat(sampleSize), 1)
            
            for x in stride(from: extent.minX + xStep/2, to: extent.maxX, by: xStep) {
                for y in stride(from: extent.minY + yStep/2, to: extent.maxY, by: yStep) {
                    if let color = sampleColor(from: image, at: CGPoint(x: x, y: y), context: context) {
                        colors.append(color)
                    }
                    if colors.count >= 25 { break } // Limit total samples
                }
                if colors.count >= 25 { break }
            }
            
            guard !colors.isEmpty else {
                return ([], 0.5, 0.5, 0.5, 0.5)
            }
            
            // Calculate metrics
            var totalBrightness = 0.0
            var totalSaturation = 0.0
            var totalWarmth = 0.0
            
            for color in colors {
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                totalBrightness += Double(brightness)
                totalSaturation += Double(saturation)
                
                // Warmth: warm colors (reds, oranges, yellows) have hue 0-0.16
                let warmthScore = hue < 0.16 || hue > 0.9 ? 1.0 : 0.0
                totalWarmth += warmthScore
            }
            
            let count = Double(colors.count)
            let avgBrightness = totalBrightness / count
            let avgSaturation = totalSaturation / count
            let avgWarmth = totalWarmth / count
            let colorfulness = avgSaturation
            
            // Extract dominant colors (simplified - just take first few)
            let dominantColors = Array(colors.prefix(5))
            
            return (dominantColors, colorfulness, avgBrightness, avgSaturation, avgWarmth)
        }
        
        private func sampleColor(from image: CIImage, at point: CGPoint, context: CIContext) -> NSColor? {
            let rect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
            guard let cgImage = context.createCGImage(image, from: rect) else { return nil }
            
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let color = bitmap.colorAt(x: 0, y: 0) else { return nil }
            
            return color
        }
        
        private func extractDominantColors(from colors: [NSColor]) -> [NSColor] {
            // Simplified: return first 5 unique colors
            var unique: [NSColor] = []
            for color in colors {
                if unique.count >= 5 { break }
                if !unique.contains(where: { areSimilarColors($0, color) }) {
                    unique.append(color)
                }
            }
            return unique
        }
        
        private func areSimilarColors(_ c1: NSColor, _ c2: NSColor) -> Bool {
            guard let rgb1 = c1.usingColorSpace(.deviceRGB),
                  let rgb2 = c2.usingColorSpace(.deviceRGB) else { return false }
            
            let threshold: CGFloat = 0.2
            return abs(rgb1.redComponent - rgb2.redComponent) < threshold &&
                   abs(rgb1.greenComponent - rgb2.greenComponent) < threshold &&
                   abs(rgb1.blueComponent - rgb2.blueComponent) < threshold
        }
        
        // MARK: - Insight Generation
        
        private func calculateMoodTrend() -> String? {
            guard yearlyInsights.count >= 2 else { return nil }
            
            let first = yearlyInsights.first!
            let last = yearlyInsights.last!
            
            let change = last.smilingFacePercentage - first.smilingFacePercentage
            
            if change > 0.1 {
                return "📈 Your photos show \(String(format: "%.0f", change * 100))% more smiling faces from \(first.year) to \(last.year), suggesting increasingly positive moments being captured."
            } else if change < -0.1 {
                return "📉 There's a \(String(format: "%.0f", abs(change) * 100))% decrease in smiling faces over time, which might indicate a shift toward more candid or artistic photography."
            } else {
                return "➡️ The emotional tone of your photos has remained relatively consistent, maintaining around \(String(format: "%.0f", last.smilingFacePercentage * 100))% positive expressions."
            }
        }
        
        private func calculateColorTrend() -> String? {
            guard yearlyInsights.count >= 2 else { return nil }
            
            let first = yearlyInsights.first!
            let last = yearlyInsights.last!
            
            var insights: [String] = []
            
            // Colorfulness
            let colorChange = last.colorfulness - first.colorfulness
            if colorChange > 0.15 {
                insights.append("Your photos have become more vibrant and colorful")
            } else if colorChange < -0.15 {
                insights.append("Your palette has shifted toward more muted, minimalist tones")
            }
            
            // Brightness
            let brightChange = last.brightness - first.brightness
            if brightChange > 0.15 {
                insights.append("lighting has become brighter")
            } else if brightChange < -0.15 {
                insights.append("you're exploring darker, moodier aesthetics")
            }
            
            // Warmth
            let warmthChange = last.warmth - first.warmth
            if warmthChange > 0.15 {
                insights.append("warmer tones (reds, oranges) are more prominent")
            } else if warmthChange < -0.15 {
                insights.append("cooler tones (blues, greens) dominate more")
            }
            
            if insights.isEmpty {
                return "Your color preferences have remained fairly consistent over time."
            } else {
                return insights.joined(separator: ", and ") + "."
            }
        }
        
        private func calculateSceneTrend() -> String? {
            guard yearlyInsights.count >= 2 else { return nil }
            
            let firstScenes = Set(yearlyInsights.first!.sceneCategories.keys)
            let lastScenes = Set(yearlyInsights.last!.sceneCategories.keys)
            
            let newScenes = lastScenes.subtracting(firstScenes)
            let lostScenes = firstScenes.subtracting(lastScenes)
            
            if !newScenes.isEmpty {
                let newList = newScenes.prefix(3).map { $0.capitalized }.joined(separator: ", ")
                return "You've started photographing new subjects: \(newList). This suggests expanding interests and exploration."
            } else if !lostScenes.isEmpty {
                return "Your focus has become more refined, concentrating on specific subjects that resonate with you."
            }
            
            return "Your photographic subjects have remained consistent, showing sustained interests."
        }
        
        private func getTopScenes() -> [(key: String, value: Int)]? {
            var combined: [String: Int] = [:]
            
            for insight in yearlyInsights {
                for (scene, count) in insight.sceneCategories {
                    combined[scene, default: 0] += count
                }
            }
            
            return combined.sorted { $0.value > $1.value }
        }
        
        private func getStyleDescription(_ insight: YearlyInsight) -> String {
            var style: [String] = []
            
            if insight.colorfulness > 0.6 {
                style.append("vibrant")
            } else if insight.colorfulness < 0.4 {
                style.append("muted")
            }
            
            if insight.brightness > 0.6 {
                style.append("bright")
            } else if insight.brightness < 0.4 {
                style.append("moody")
            }
            
            if insight.saturation > 0.6 {
                style.append("saturated")
            } else if insight.saturation < 0.4 {
                style.append("desaturated")
            }
            
            return style.isEmpty ? "balanced" : style.joined(separator: ", ")
        }
        
        private func generateInterpretations() -> [String]? {
            guard yearlyInsights.count >= 2 else { return nil }
            
            var interpretations: [String] = []
            
            let first = yearlyInsights.first!
            let last = yearlyInsights.last!
            
            // Face count interpretation
            let faceChange = last.averageFacesPerPhoto - first.averageFacesPerPhoto
            if faceChange > 0.5 {
                interpretations.append("More people in your photos suggests increased social connection and group activities.")
            } else if faceChange < -0.5 {
                interpretations.append("Fewer faces might indicate a shift toward landscape/object photography, or more solo pursuits.")
            }
            
            // Mood interpretation
            let moodChange = last.smilingFacePercentage - first.smilingFacePercentage
            if moodChange > 0.1 {
                interpretations.append("The increase in positive expressions could reflect happier times or more celebration-focused photography.")
            }
            
            // Color interpretation
            let colorChange = last.colorfulness - first.colorfulness
            if colorChange > 0.15 {
                interpretations.append("More vibrant colors might suggest increased energy, optimism, or experimentation with editing styles.")
            } else if colorChange < -0.15 {
                interpretations.append("Muted colors could indicate a more minimalist aesthetic, professional approach, or reflective mood.")
            }
            
            // Brightness interpretation
            let brightChange = last.brightness - first.brightness
            if brightChange < -0.15 {
                interpretations.append("Darker imagery might reflect artistic growth, exploring dramatic lighting, or documenting evening activities.")
            }
            
            // Overall growth
            interpretations.append("Your photography shows evolution and growth, reflecting changes in your life, interests, and creative expression.")
            
            return interpretations
        }
    }
}

// MARK: - Extensions

extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

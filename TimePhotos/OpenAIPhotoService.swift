//
//  OpenAIPhotoService.swift
//  TimePhotos
//
//  Created for TimePhotos App.
//

import Foundation
import Photos
import Vision
import CoreLocation

@MainActor
class OpenAIPhotoService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing: Bool = false
    @Published var apiKey: String = "" {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "OpenAIAPIKey")
        }
    }
    
    private let albums: [(year: Int, month: Int?, album: PHAssetCollection)]
    private let allAlbums: [ContentView.AlbumInfo]
    private let allPhotos: [(year: Int, month: Int?, assets: [PHAsset])]
    private let photosNotInAlbums: (photoCount: Int, videoCount: Int)
    
    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    
    init(albums: [(year: Int, month: Int?, album: PHAssetCollection)], allAlbums: [ContentView.AlbumInfo], allPhotos: [(year: Int, month: Int?, assets: [PHAsset])], photosNotInAlbums: (photoCount: Int, videoCount: Int)) {
        self.albums = albums
        self.allAlbums = allAlbums
        self.allPhotos = allPhotos
        self.photosNotInAlbums = photosNotInAlbums
        
        // Load API key from UserDefaults
        if let savedKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"), !savedKey.isEmpty {
            self.apiKey = savedKey
        }
    }
    
    func sendMessage(_ text: String) async {
        guard !apiKey.isEmpty else {
            let errorMessage = ChatMessage(content: "Please set your OpenAI API key in settings. Go to Settings > OpenAI API Key and enter your key.", isUser: false)
            messages.append(errorMessage)
            return
        }
        
        // Add user message
        let userMessage = ChatMessage(content: text, isUser: true)
        messages.append(userMessage)
        isProcessing = true
        
        do {
            // Build comprehensive photo library context
            let context = await buildComprehensiveContext()
            
            // Prepare messages for OpenAI API
            var apiMessages: [[String: String]] = []
            
            // System message with context
            apiMessages.append([
                "role": "system",
                "content": """
                You are a helpful AI assistant with access to a user's COMPLETE Apple Photos library. You have access to:
                - ALL items in the library (both in albums AND not in albums)
                - Full PhotoKit metadata (dates, locations, media types, etc.)
                - Comprehensive media type breakdowns including:
                  * Images (all images including photos, live photos, screenshots, panoramas, etc.)
                  * Photos (regular photos, excluding live photos, screenshots, panoramas, portraits)
                  * Live Photos (specifically tracked and counted separately from regular photos)
                  * Videos, Selfies, Portraits, Panoramas, Time-lapse, Slo-mo, Cinematic, Bursts
                  * Screenshots, Screen Recordings, Spatial, Animated, RAW
                  * Favorites, Hidden, Edited items, Recently Added, etc.
                - Album information and organization
                - Complete photo/video counts and statistics
                - Temporal data (years, months, dates, times)
                - Location data when available
                - Items in albums vs items not in albums
                - Favorite status, hidden status, edited status
                - Creation dates and modification dates
                
                IMPORTANT: Photos and Live Photos are tracked separately. "Photos" refers to regular photos, while "Live Photos" are a special type of image that includes a short video clip.
                
                The context below includes ALL items from the entire Photos library, not just items in albums. You can answer questions about any aspect of the user's complete photo collection.
                
                Photo Library Context (COMPLETE LIBRARY):
                \(context)
                
                Provide helpful, conversational responses about the user's photo library. Be natural, friendly, and detailed when appropriate. Always refer to the complete library data provided.
                """
            ])
            
            // Add conversation history (last 10 messages to stay within token limits)
            let recentMessages = messages.suffix(10)
            for message in recentMessages {
                apiMessages.append([
                    "role": message.isUser ? "user" : "assistant",
                    "content": message.content
                ])
            }
            
            // Make API request
            let response = try await callOpenAIAPI(messages: apiMessages)
            
            // Add AI response
            let aiMessage = ChatMessage(content: response, isUser: false)
            messages.append(aiMessage)
            isProcessing = false
            
        } catch {
            let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription). Please check your API key and internet connection.", isUser: false)
            messages.append(errorMessage)
            isProcessing = false
        }
    }
    
    private func buildComprehensiveContext() async -> String {
        var context = ""
        
        // Collect ALL assets from the entire library (allPhotos contains everything)
        var allAssets: [PHAsset] = []
        for (_, _, assets) in allPhotos {
            allAssets.append(contentsOf: assets)
        }
        
        // Remove duplicates (in case assets appear in multiple year/month groups)
        var uniqueAssets: Set<String> = []
        var deduplicatedAssets: [PHAsset] = []
        for asset in allAssets {
            if !uniqueAssets.contains(asset.localIdentifier) {
                uniqueAssets.insert(asset.localIdentifier)
                deduplicatedAssets.append(asset)
            }
        }
        allAssets = deduplicatedAssets
        
        // Comprehensive categorization of ALL assets
        var mediaTypeCounts: [String: Int] = [
            "Total Items": allAssets.count,
            "Images": 0,  // All images (photos + live photos + screenshots, etc.)
            "Photos": 0,  // Regular photos (images that are NOT live photos, screenshots, panoramas, etc.)
            "Videos": 0,
            "Selfies": 0,
            "Live Photos": 0,  // Live photos (subset of images)
            "Portraits": 0,
            "Long Exposure": 0,
            "Panoramas": 0,
            "Time-lapse": 0,
            "Slo-mo": 0,
            "Cinematic": 0,
            "Bursts": 0,
            "Screenshots": 0,
            "Screen Recordings": 0,
            "Spatial": 0,
            "Animated": 0,
            "RAW": 0,
            "Favorites": 0,
            "Hidden": 0,
            "Recently Deleted": 0,
            "Duplicates": 0,
            "Receipts": 0,
            "Handwriting": 0,
            "Illustrations": 0,
            "QR Codes": 0,
            "Recently Saved": 0,
            "Recently Viewed": 0,
            "Recently Edited": 0,
            "Recently Shared": 0,
            "Documents": 0,
            "Imports": 0,
            "Recently Added": 0,
            "Edited": 0,
            "Not Edited": 0
        ]
        
        // Track items in albums vs not in albums
        var assetsInAlbums: Set<String> = []
        for album in allAlbums {
            let albumAssets = PHAsset.fetchAssets(in: album.album, options: nil)
            albumAssets.enumerateObjects { asset, _, _ in
                assetsInAlbums.insert(asset.localIdentifier)
            }
        }
        
        var itemsInAlbums = 0
        var itemsNotInAlbums = 0
        
        // Get date ranges for "recently" categories
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        // Query smart albums for special categories
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        var recentlyDeletedCount = 0
        var duplicatesCount = 0
        var screenshotsCount = 0
        var selfiesCount = 0
        var videosCount = 0
        var favoritesCount = 0
        var hiddenCount = 0
        var panoramasCount = 0
        var livePhotosCount = 0
        var portraitsCount = 0
        var timeLapseCount = 0
        var slowMotionCount = 0
        var cinematicCount = 0
        var burstsCount = 0
        var slomoVideosCount = 0
        var recentlyAddedCount = 0
        
        smartAlbums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? ""
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            let count = assets.count
            
            switch title.lowercased() {
            case "recently deleted":
                recentlyDeletedCount = count
            case "duplicates":
                duplicatesCount = count
            case "screenshots":
                screenshotsCount = max(screenshotsCount, count)
            case "selfies":
                selfiesCount = max(selfiesCount, count)
            case "videos":
                videosCount = max(videosCount, count)
            case "favorites":
                favoritesCount = max(favoritesCount, count)
            case "hidden":
                hiddenCount = max(hiddenCount, count)
            case "panoramas":
                panoramasCount = max(panoramasCount, count)
            case "live photos":
                livePhotosCount = max(livePhotosCount, count)
            case "portraits":
                portraitsCount = max(portraitsCount, count)
            case "time-lapse":
                timeLapseCount = max(timeLapseCount, count)
            case "slo-mo":
                slowMotionCount = max(slowMotionCount, count)
            case "cinematic":
                cinematicCount = max(cinematicCount, count)
            case "bursts":
                burstsCount = max(burstsCount, count)
            case "recently added":
                recentlyAddedCount = max(recentlyAddedCount, count)
            case "receipts":
                mediaTypeCounts["Receipts"] = max(mediaTypeCounts["Receipts"] ?? 0, count)
            case "handwriting":
                mediaTypeCounts["Handwriting"] = max(mediaTypeCounts["Handwriting"] ?? 0, count)
            case "illustrations":
                mediaTypeCounts["Illustrations"] = max(mediaTypeCounts["Illustrations"] ?? 0, count)
            case "qr codes":
                mediaTypeCounts["QR Codes"] = max(mediaTypeCounts["QR Codes"] ?? 0, count)
            case "documents":
                mediaTypeCounts["Documents"] = max(mediaTypeCounts["Documents"] ?? 0, count)
            case "imports":
                mediaTypeCounts["Imports"] = max(mediaTypeCounts["Imports"] ?? 0, count)
            default:
                break
            }
        }
        
        // Update counts from smart albums where available
        if recentlyDeletedCount > 0 {
            mediaTypeCounts["Recently Deleted"] = recentlyDeletedCount
        }
        if duplicatesCount > 0 {
            mediaTypeCounts["Duplicates"] = duplicatesCount
        }
        if selfiesCount > 0 {
            mediaTypeCounts["Selfies"] = max(mediaTypeCounts["Selfies"] ?? 0, selfiesCount)
        }
        if burstsCount > 0 {
            mediaTypeCounts["Bursts"] = max(mediaTypeCounts["Bursts"] ?? 0, burstsCount)
        }
        
        // Categorize each asset
        for asset in allAssets {
            // Basic media types
            if asset.mediaType == .image {
                mediaTypeCounts["Images"] = (mediaTypeCounts["Images"] ?? 0) + 1
                
                // Track regular photos (images that are NOT special types)
                // A regular photo is an image that is NOT a live photo, screenshot, panorama, or portrait
                let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                let isPanorama = asset.mediaSubtypes.contains(.photoPanorama)
                let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
                
                // Count as regular photo if it's not any of the special image types
                if !isLivePhoto && !isScreenshot && !isPanorama && !isPortrait {
                    mediaTypeCounts["Photos"] = (mediaTypeCounts["Photos"] ?? 0) + 1
                }
            } else if asset.mediaType == .video {
                mediaTypeCounts["Videos"] = (mediaTypeCounts["Videos"] ?? 0) + 1
            }
            
            // Track in/out of albums
            if assetsInAlbums.contains(asset.localIdentifier) {
                itemsInAlbums += 1
            } else {
                itemsNotInAlbums += 1
            }
            
            // Media subtypes - track all special types
            if asset.mediaSubtypes.contains(.photoLive) {
                mediaTypeCounts["Live Photos"] = (mediaTypeCounts["Live Photos"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.photoDepthEffect) {
                mediaTypeCounts["Portraits"] = (mediaTypeCounts["Portraits"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.photoPanorama) {
                mediaTypeCounts["Panoramas"] = (mediaTypeCounts["Panoramas"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                mediaTypeCounts["Screenshots"] = (mediaTypeCounts["Screenshots"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.videoTimelapse) {
                mediaTypeCounts["Time-lapse"] = (mediaTypeCounts["Time-lapse"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.videoHighFrameRate) {
                mediaTypeCounts["Slo-mo"] = (mediaTypeCounts["Slo-mo"] ?? 0) + 1
            }
            if asset.mediaSubtypes.contains(.videoCinematic) {
                mediaTypeCounts["Cinematic"] = (mediaTypeCounts["Cinematic"] ?? 0) + 1
            }
            
            // Asset properties
            if asset.isFavorite {
                mediaTypeCounts["Favorites"] = (mediaTypeCounts["Favorites"] ?? 0) + 1
            }
            if asset.isHidden {
                mediaTypeCounts["Hidden"] = (mediaTypeCounts["Hidden"] ?? 0) + 1
            }
            if asset.hasAdjustments {
                mediaTypeCounts["Edited"] = (mediaTypeCounts["Edited"] ?? 0) + 1
            } else {
                mediaTypeCounts["Not Edited"] = (mediaTypeCounts["Not Edited"] ?? 0) + 1
            }
            
            // Recently added (creation date within last 30 days)
            if let creationDate = asset.creationDate, creationDate >= thirtyDaysAgo {
                mediaTypeCounts["Recently Added"] = (mediaTypeCounts["Recently Added"] ?? 0) + 1
            }
            
            // Recently edited (modification date within last 30 days)
            if let modificationDate = asset.modificationDate, modificationDate >= thirtyDaysAgo {
                mediaTypeCounts["Recently Edited"] = (mediaTypeCounts["Recently Edited"] ?? 0) + 1
            }
            
            // Check for burst photos (represented as PHAssetCollection)
            // Note: Burst detection requires checking if asset is part of a burst collection
            // This is a simplified check - full burst detection would require additional queries
        }
        
        // Calculate year range
        let years = Set(allPhotos.map { $0.year }).sorted()
        let yearRange = years.isEmpty ? "unknown" : "\(years.first ?? 0) to \(years.last ?? 0)"
        
        // Build context string
        context += """
        === COMPLETE PHOTO LIBRARY OVERVIEW ===
        - Total items (ENTIRE library): \(allAssets.count)
        - Items in albums: \(itemsInAlbums)
        - Items NOT in albums: \(itemsNotInAlbums)
        - Year range: \(yearRange)
        - Years with items: \(years.count)
        - Total albums: \(allAlbums.count)
        
        """
        
        // Comprehensive media type breakdown
        context += "=== COMPREHENSIVE MEDIA TYPE BREAKDOWN (ALL ITEMS) ===\n"
        context += "Note: 'Images' includes all images (photos, live photos, screenshots, panoramas, etc.).\n"
        context += "'Photos' refers specifically to regular photos (excluding live photos, screenshots, panoramas, portraits).\n"
        context += "'Live Photos' are a subset of images.\n\n"
        for (type, count) in mediaTypeCounts.sorted(by: { $0.value > $1.value }) where count > 0 {
            context += "- \(type): \(count)\n"
        }
        context += "\n"
        
        // Year-by-year breakdown (ALL items)
        // NOTE: allPhotos contains both monthly entries AND yearly totals (month: nil)
        // We need to use ONLY the yearly totals to avoid double-counting
        context += "=== YEAR-BY-YEAR BREAKDOWN (ALL ITEMS) ===\n"
        for year in years.suffix(10) { // Last 10 years
            // Get only the yearly total entry (month == nil) to avoid double-counting
            let yearTotalEntry = allPhotos.first { $0.year == year && $0.month == nil }
            
            guard let yearEntry = yearTotalEntry else {
                // Fallback: if no yearly total exists, use monthly entries but deduplicate
                let monthlyEntries = allPhotos.filter { $0.year == year && $0.month != nil }
                var uniqueAssetsForYear: Set<String> = []
                var yearImageCount = 0
                var yearPhotoCount = 0
                var yearVideoCount = 0
                var yearFavorites = 0
                var yearLivePhotos = 0
                var yearPortraits = 0
                var yearScreenshots = 0
                
                for (_, _, assets) in monthlyEntries {
                    for asset in assets {
                        if !uniqueAssetsForYear.contains(asset.localIdentifier) {
                            uniqueAssetsForYear.insert(asset.localIdentifier)
                            
                            if asset.mediaType == .image {
                                yearImageCount += 1
                                let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                                let isPanorama = asset.mediaSubtypes.contains(.photoPanorama)
                                let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
                                
                                if !isLivePhoto && !isScreenshot && !isPanorama && !isPortrait {
                                    yearPhotoCount += 1
                                }
                            } else if asset.mediaType == .video {
                                yearVideoCount += 1
                            }
                            if asset.isFavorite { yearFavorites += 1 }
                            if asset.mediaSubtypes.contains(.photoLive) { yearLivePhotos += 1 }
                            if asset.mediaSubtypes.contains(.photoDepthEffect) { yearPortraits += 1 }
                            if asset.mediaSubtypes.contains(.photoScreenshot) { yearScreenshots += 1 }
                        }
                    }
                }
                
                let totalYearItems = uniqueAssetsForYear.count
                context += "- \(year): \(totalYearItems) total items"
                context += " (\(yearImageCount) images: \(yearPhotoCount) photos"
                if yearLivePhotos > 0 {
                    context += ", \(yearLivePhotos) live photos"
                }
                if yearPortraits > 0 {
                    context += ", \(yearPortraits) portraits"
                }
                if yearScreenshots > 0 {
                    context += ", \(yearScreenshots) screenshots"
                }
                context += "; \(yearVideoCount) videos)"
                if yearFavorites > 0 { context += ", \(yearFavorites) favorites" }
                context += "\n"
                continue
            }
            
            // Use the yearly total entry (already deduplicated)
            let totalYearItems = yearEntry.assets.count
            
            // Count by type for this year (using deduplicated yearly total)
            var yearImageCount = 0
            var yearPhotoCount = 0  // Regular photos (not live photos, screenshots, etc.)
            var yearVideoCount = 0
            var yearFavorites = 0
            var yearLivePhotos = 0
            var yearPortraits = 0
            var yearScreenshots = 0
            
            for asset in yearEntry.assets {
                if asset.mediaType == .image {
                    yearImageCount += 1
                    
                    // Count regular photos (images that are NOT special types)
                    let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                    let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                    let isPanorama = asset.mediaSubtypes.contains(.photoPanorama)
                    let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
                    
                    if !isLivePhoto && !isScreenshot && !isPanorama && !isPortrait {
                        yearPhotoCount += 1
                    }
                } else if asset.mediaType == .video {
                    yearVideoCount += 1
                }
                if asset.isFavorite { yearFavorites += 1 }
                if asset.mediaSubtypes.contains(.photoLive) { yearLivePhotos += 1 }
                if asset.mediaSubtypes.contains(.photoDepthEffect) { yearPortraits += 1 }
                if asset.mediaSubtypes.contains(.photoScreenshot) { yearScreenshots += 1 }
            }
            
            context += "- \(year): \(totalYearItems) total items"
            context += " (\(yearImageCount) images: \(yearPhotoCount) photos"
            if yearLivePhotos > 0 {
                context += ", \(yearLivePhotos) live photos"
            }
            if yearPortraits > 0 {
                context += ", \(yearPortraits) portraits"
            }
            if yearScreenshots > 0 {
                context += ", \(yearScreenshots) screenshots"
            }
            context += "; \(yearVideoCount) videos)"
            if yearFavorites > 0 { context += ", \(yearFavorites) favorites" }
            context += "\n"
        }
        context += "\n"
        
        // Monthly breakdown for recent years (ALL items)
        context += "=== MONTHLY BREAKDOWN (Recent Years - ALL ITEMS) ===\n"
        for year in years.suffix(2) { // Last 2 years
            context += "\(year):\n"
            for month in 1...12 {
                let monthAssets = allPhotos.filter { $0.year == year && $0.month == month }
                let monthTotal = monthAssets.reduce(0) { $0 + $1.assets.count }
                if monthTotal > 0 {
                    let monthName = Calendar.current.monthSymbols[month - 1]
                    context += "  - \(monthName): \(monthTotal) items\n"
                }
            }
        }
        context += "\n"
        
        // Album summary (condensed)
        context += "=== ALBUM SUMMARY ===\n"
        context += "Total albums: \(allAlbums.count)\n"
        let totalInAlbums = allAlbums.reduce(0) { $0 + $1.photoCount + $1.videoCount }
        context += "Total items in albums: \(totalInAlbums)\n"
        if allAlbums.count > 0 {
            context += "Sample album names: "
            let sampleAlbums = allAlbums.prefix(20).map { $0.albumName }
            context += sampleAlbums.joined(separator: ", ")
            context += "\n"
        }
        context += "\n"
        
        // Items not in albums detail
        if itemsNotInAlbums > 0 {
            context += "=== ITEMS NOT IN ALBUMS ===\n"
            context += "- Total: \(itemsNotInAlbums) items\n"
            context += "- Photos: \(photosNotInAlbums.photoCount)\n"
            context += "- Videos: \(photosNotInAlbums.videoCount)\n"
            context += "\n"
        }
        
        // Date/time information
        context += "=== DATE/TIME INFORMATION ===\n"
        let sortedByDate = allAssets.sorted { asset1, asset2 in
            guard let date1 = asset1.creationDate, let date2 = asset2.creationDate else { return false }
            return date1 < date2
        }
        if let firstAsset = sortedByDate.first, let firstDate = firstAsset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            context += "- Oldest item: \(formatter.string(from: firstDate))\n"
        }
        if let lastAsset = sortedByDate.last, let lastDate = lastAsset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            context += "- Newest item: \(formatter.string(from: lastDate))\n"
        }
        context += "\n"
        
        // Note about data availability
        context += "=== DATA AVAILABILITY NOTE ===\n"
        context += "This context includes ALL items from the complete Photos library (both in albums and not in albums).\n"
        context += "All media types, dates, locations, and metadata are included where available through PhotoKit.\n"
        context += "Some categories (like 'Recently Saved', 'Recently Viewed', 'Recently Shared', 'Pinned') may require additional analysis or may not be directly available through PhotoKit's standard API.\n"
        context += "\n"
        
        return context
    }
    
    private func callOpenAIAPI(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API request failed with status \(httpResponse.statusCode)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Helper method to get detailed asset metadata (can be called for specific queries)
    func getAssetMetadata(_ asset: PHAsset) async -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        metadata["mediaType"] = asset.mediaType == .image ? "image" : asset.mediaType == .video ? "video" : "audio"
        metadata["creationDate"] = asset.creationDate?.description ?? "unknown"
        metadata["modificationDate"] = asset.modificationDate?.description ?? "unknown"
        metadata["pixelWidth"] = asset.pixelWidth
        metadata["pixelHeight"] = asset.pixelHeight
        metadata["duration"] = asset.duration
        metadata["isFavorite"] = asset.isFavorite
        metadata["isHidden"] = asset.isHidden
        
        // Location
        if let location = asset.location {
            metadata["latitude"] = location.coordinate.latitude
            metadata["longitude"] = location.coordinate.longitude
            metadata["altitude"] = location.altitude
        }
        
        // Media subtypes
        var subtypes: [String] = []
        if asset.mediaSubtypes.contains(.photoLive) { subtypes.append("live") }
        if asset.mediaSubtypes.contains(.photoPanorama) { subtypes.append("panorama") }
        if asset.mediaSubtypes.contains(.photoHDR) { subtypes.append("HDR") }
        if asset.mediaSubtypes.contains(.photoScreenshot) { subtypes.append("screenshot") }
        if asset.mediaSubtypes.contains(.photoDepthEffect) { subtypes.append("portrait") }
        if asset.mediaSubtypes.contains(.videoTimelapse) { subtypes.append("timelapse") }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) { subtypes.append("slowMotion") }
        if asset.mediaSubtypes.contains(.videoCinematic) { subtypes.append("cinematic") }
        metadata["subtypes"] = subtypes
        
        return metadata
    }
}


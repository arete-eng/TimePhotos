//
//  PhotoLibraryAI.swift
//  TimePhotos
//
//  Created for TimePhotos App.
//

import Foundation
import Photos
import NaturalLanguage
import Vision
import CoreML

// Try to import FoundationModels if available (Apple Intelligence on-device LLM)
// Note: This framework may not be publicly available yet in all macOS versions
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date = Date()
}

@MainActor
class PhotoLibraryAI: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing: Bool = false
    
    private let albums: [(year: Int, month: Int?, album: PHAssetCollection)]
    private let allAlbums: [ContentView.AlbumInfo]
    private let allPhotos: [(year: Int, month: Int?, assets: [PHAsset])]
    private let photosNotInAlbums: (photoCount: Int, videoCount: Int)
    
    init(albums: [(year: Int, month: Int?, album: PHAssetCollection)], allAlbums: [ContentView.AlbumInfo], allPhotos: [(year: Int, month: Int?, assets: [PHAsset])], photosNotInAlbums: (photoCount: Int, videoCount: Int)) {
        self.albums = albums
        self.allAlbums = allAlbums
        self.allPhotos = allPhotos
        self.photosNotInAlbums = photosNotInAlbums
    }
    
    func sendMessage(_ text: String) async {
        // Add user message
        let userMessage = ChatMessage(content: text, isUser: true)
        messages.append(userMessage)
        isProcessing = true
        
        // Process and generate response
        let response = await processQuery(text)
        
        // Add AI response
        let aiMessage = ChatMessage(content: response, isUser: false)
        messages.append(aiMessage)
        isProcessing = false
    }
    
    private func processQuery(_ query: String) async -> String {
        // First, try to use Apple Intelligence Foundation Models if available
        #if canImport(FoundationModels)
        if let aiResponse = await generateWithAppleIntelligence(query) {
            return aiResponse
        }
        #endif
        
        // Fallback to enhanced rule-based system with conversational responses
        return await processQueryWithEnhancedNL(query)
    }
    
    #if canImport(FoundationModels)
    private func generateWithAppleIntelligence(_ query: String) async -> String? {
        // Attempt to use Foundation Models framework for conversational AI
        // This would use Apple's on-device LLM
        // Note: The actual API may vary - this is a placeholder for the intended usage
        
        // Build context about the photo library
        let context = buildPhotoLibraryContext()
        let prompt = """
        You are a helpful assistant for a photo library app. The user is asking about their photos.
        
        Photo Library Context:
        \(context)
        
        User Question: \(query)
        
        Provide a helpful, conversational response about their photo library. Be natural and friendly.
        """
        
        // TODO: Use FoundationModels API when available
        // Example (actual API may differ):
        // let request = LLMRequest(prompt: prompt)
        // return try? await request.generate()
        
        return nil // Return nil to fall back to enhanced NL processing
    }
    #endif
    
    private func buildPhotoLibraryContext() -> String {
        let albumYears = Set(albums.map { $0.year })
        let photoYears = Set(allPhotos.map { $0.year })
        let years = Array(albumYears.union(photoYears)).sorted()
        let yearRange = years.isEmpty ? "unknown" : "\(years.first ?? 0) to \(years.last ?? 0)"
        
        let totalItemsInAlbums = allAlbums.reduce(0) { $0 + $1.photoCount + $1.videoCount }
        let totalItems = totalItemsInAlbums + photosNotInAlbums.photoCount + photosNotInAlbums.videoCount
        
        return """
        - Total albums: \(albums.count)
        - Total items (in albums): \(totalItemsInAlbums)
        - Photos not in albums: \(photosNotInAlbums.photoCount)
        - Videos not in albums: \(photosNotInAlbums.videoCount)
        - Total items (full library): \(totalItems)
        - Year range: \(yearRange)
        - Years with items: \(years.count)
        - All media types included: photos, videos, live photos, portraits, panoramas, screenshots, etc.
        """
    }
    
    private func processQueryWithEnhancedNL(_ query: String) async -> String {
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Use Natural Language framework for better understanding
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = queryLower
        
        // Extract key terms
        var keywords: [String] = []
        tagger.enumerateTags(in: queryLower.startIndex..<queryLower.endIndex, unit: .word, scheme: .lexicalClass) { _, tokenRange in
            let word = String(queryLower[tokenRange])
            if word.count > 2 { // Filter out very short words
                keywords.append(word)
            }
            return true
        }
        
        // Smart intent detection with context awareness
        var intent: QueryIntent = .general
        
        // Check for album-related queries (including temporal context)
        let hasAlbumKeyword = queryLower.contains("album") || queryLower.contains("folder") || queryLower.contains("collection")
        let hasTemporalKeyword = queryLower.contains("year") || queryLower.contains("when") || queryLower.contains("date") || queryLower.contains("time") || queryLower.contains("month") || queryLower.contains("from")
        let hasCountKeyword = queryLower.contains("how many") || queryLower.contains("count") || queryLower.contains("total") || queryLower.contains("number of")
        
        // Complex queries: "albums from 2023" should be album query with temporal context
        if hasAlbumKeyword && (hasTemporalKeyword || extractYear(from: query) != nil) {
            intent = .albumQuery
        } else if hasAlbumKeyword && (queryLower.contains("tell me about") || queryLower.contains("what") || queryLower.contains("list") || queryLower.contains("show")) {
            intent = .albumQuery
        } else if hasCountKeyword {
            intent = .countQuery
        } else if hasTemporalKeyword {
            intent = .temporalQuery
        } else if queryLower.contains("where") || queryLower.contains("location") || queryLower.contains("place") {
            intent = .locationQuery
        } else if queryLower.contains("photo") || queryLower.contains("image") || queryLower.contains("picture") {
            intent = .photoQuery
        } else if hasAlbumKeyword {
            intent = .albumQuery
        }
        
        // Process based on intent with conversational responses
        switch intent {
        case .countQuery:
            return await handleCountQuery(query: query, keywords: keywords)
        case .temporalQuery:
            return await handleTemporalQuery(query: query, keywords: keywords)
        case .locationQuery:
            return await handleLocationQuery(query: query, keywords: keywords)
        case .albumQuery:
            return await handleAlbumQuery(query: query, keywords: keywords)
        case .photoQuery:
            return await handlePhotoQuery(query: query, keywords: keywords)
        case .general:
            return await handleGeneralQuery(query: query, keywords: keywords)
        }
    }
    
    private func extractYear(from query: String) -> Int? {
        let yearPattern = #"\b(19|20)\d{2}\b|\b'\d{2}\b"#
        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) {
            if let yearRange = Range(match.range, in: query) {
                let yearStr = String(query[yearRange]).replacingOccurrences(of: "'", with: "")
                if let year = Int(yearStr) {
                    return year < 100 ? 2000 + year : year
                }
            }
        }
        return nil
    }
    
    private func extractMonth(from query: String) -> Int? {
        let queryLower = query.lowercased()
        let monthNames = ["january", "february", "march", "april", "may", "june",
                         "july", "august", "september", "october", "november", "december"]
        let monthAbbrevs = ["jan", "feb", "mar", "apr", "may", "jun",
                           "jul", "aug", "sep", "oct", "nov", "dec"]
        
        for (index, monthName) in monthNames.enumerated() {
            if queryLower.contains(monthName) {
                return index + 1
            }
        }
        
        for (index, monthAbbrev) in monthAbbrevs.enumerated() {
            if queryLower.contains(monthAbbrev) {
                return index + 1
            }
        }
        
        return nil
    }
    
    private func handleCountQuery(query: String, keywords: [String]) async -> String {
        // Extract year if mentioned
        let targetYear = extractYear(from: query)
        let targetMonth = extractMonth(from: query)
        
        if let year = targetYear {
            // Count items from allPhotos for that year
            let yearAssets = allPhotos.filter { $0.year == year }
            let monthAssets = targetMonth != nil ? yearAssets.filter { $0.month == targetMonth } : nil
            
            let assetsToCount = monthAssets ?? yearAssets
            let totalItems = assetsToCount.reduce(0) { $0 + $1.assets.count }
            
            // Count by media type
            var photoCount = 0
            var videoCount = 0
            for (_, _, assets) in assetsToCount {
                for asset in assets {
                    if asset.mediaType == .image {
                        photoCount += 1
                    } else if asset.mediaType == .video {
                        videoCount += 1
                    }
                }
            }
            
            if totalItems > 0 {
                var response = ""
                if let month = targetMonth {
                    let monthName = Calendar.current.monthSymbols[month - 1]
                    response = "In \(monthName) \(year), you have \(totalItems) total items"
                } else {
                    response = "In \(year), you have \(totalItems) total items"
                }
                
                if photoCount > 0 && videoCount > 0 {
                    response += " (\(photoCount) photos and \(videoCount) videos)"
                } else if photoCount > 0 {
                    response += " (\(photoCount) photos)"
                } else if videoCount > 0 {
                    response += " (\(videoCount) videos)"
                }
                
                // Count albums for that year
                let yearAlbums = albums.filter { $0.year == year }
                if !yearAlbums.isEmpty {
                    response += " across \(yearAlbums.count) \(yearAlbums.count == 1 ? "album" : "albums")"
                }
                response += ". That's quite a collection!"
                return response
            } else {
                if let month = targetMonth {
                    let monthName = Calendar.current.monthSymbols[month - 1]
                    return "I don't see any items from \(monthName) \(year) in your library. Would you like to know about a different time period?"
                } else {
                    return "I don't see any items from \(year) in your library. Would you like to know about a different year?"
                }
            }
        } else {
            // Overall count - use full library data
            let totalItemsInAlbums = await countAllMediaInAlbums(albums.map { $0.album })
            let totalItems = totalItemsInAlbums + photosNotInAlbums.photoCount + photosNotInAlbums.videoCount
            let totalAlbums = albums.count
            let albumYears = Set(albums.map { $0.year })
            let photoYears = Set(allPhotos.map { $0.year })
            let years = Array(albumYears.union(photoYears)).sorted()
            
            if totalItems > 0 {
                var response = "Your photo library contains \(totalItems) total items"
                
                // Break down by type
                var typeBreakdown: [String] = []
                let totalPhotos = totalItemsInAlbums + photosNotInAlbums.photoCount // Approximate
                let totalVideos = photosNotInAlbums.videoCount // Approximate
                if totalPhotos > 0 { typeBreakdown.append("\(totalPhotos) photos") }
                if totalVideos > 0 { typeBreakdown.append("\(totalVideos) videos") }
                if !typeBreakdown.isEmpty {
                    response += " (\(typeBreakdown.joined(separator: ", ")))"
                }
                
                if totalAlbums > 0 {
                    response += " across \(totalAlbums) \(totalAlbums == 1 ? "album" : "albums")"
                    if photosNotInAlbums.photoCount > 0 || photosNotInAlbums.videoCount > 0 {
                        let notInAlbums = photosNotInAlbums.photoCount + photosNotInAlbums.videoCount
                        response += ", with \(notInAlbums) items not in albums"
                    }
                } else if photosNotInAlbums.photoCount > 0 || photosNotInAlbums.videoCount > 0 {
                    let notInAlbums = photosNotInAlbums.photoCount + photosNotInAlbums.videoCount
                    response += " (all \(notInAlbums) are not in albums)"
                }
                
                if let firstYear = years.first, let lastYear = years.last, firstYear != lastYear {
                    response += ", spanning \(years.count) years from \(firstYear) to \(lastYear)"
                } else if let year = years.first {
                    response += " from \(year)"
                }
                response += ". That's an impressive collection!"
                return response
            } else {
                return "I don't see any items in your library yet. Make sure you've granted photo library access!"
            }
        }
    }
    
    private func handleTemporalQuery(query: String, keywords: [String]) async -> String {
        let targetYear = extractYear(from: query)
        let targetMonth = extractMonth(from: query)
        
        if let year = targetYear, let month = targetMonth {
            // Specific month and year
            let monthAssets = allPhotos.filter { $0.year == year && $0.month == month }
            let totalItems = monthAssets.reduce(0) { $0 + $1.assets.count }
            
            var photoCount = 0
            var videoCount = 0
            for (_, _, assets) in monthAssets {
                for asset in assets {
                    if asset.mediaType == .image {
                        photoCount += 1
                    } else if asset.mediaType == .video {
                        videoCount += 1
                    }
                }
            }
            
            let monthName = Calendar.current.monthSymbols[month - 1]
            var response = "In \(monthName) \(year), you have \(totalItems) total items"
            if photoCount > 0 && videoCount > 0 {
                response += " (\(photoCount) photos and \(videoCount) videos)"
            } else if photoCount > 0 {
                response += " (\(photoCount) photos)"
            } else if videoCount > 0 {
                response += " (\(videoCount) videos)"
            }
            response += " in your entire library."
            return response
        } else if let year = targetYear {
            // Just year
            let yearAssets = allPhotos.filter { $0.year == year }
            let totalItems = yearAssets.reduce(0) { $0 + $1.assets.count }
            
            var photoCount = 0
            var videoCount = 0
            for (_, _, assets) in yearAssets {
                for asset in assets {
                    if asset.mediaType == .image {
                        photoCount += 1
                    } else if asset.mediaType == .video {
                        videoCount += 1
                    }
                }
            }
            
            var response = "In \(year), you have \(totalItems) total items"
            if photoCount > 0 && videoCount > 0 {
                response += " (\(photoCount) photos and \(videoCount) videos)"
            } else if photoCount > 0 {
                response += " (\(photoCount) photos)"
            } else if videoCount > 0 {
                response += " (\(videoCount) videos)"
            }
            response += " in your entire library."
            return response
        } else {
            // General temporal info
            let albumYears = Set(albums.map { $0.year })
            let photoYears = Set(allPhotos.map { $0.year })
            let years = Array(albumYears.union(photoYears)).sorted()
            
            if let firstYear = years.first, let lastYear = years.last, firstYear != lastYear {
                return "Your library spans from \(firstYear) to \(lastYear), covering \(years.count) years. That's quite a journey through time! Ask me about a specific year or month to learn more."
            } else if let year = years.first {
                return "Your library contains items from \(year). Ask me about a specific month to see more details!"
            }
            return "I can help you explore your library by time period. Try asking about a specific year (like '2023') or month (like 'January 2024')!"
        }
    }
    
    private func handleLocationQuery(query: String, keywords: [String]) async -> String {
        // This would require location data from photos
        // For now, provide a general response
        return "I can see you have photos with location data. To get specific location information, I'd need to analyze the geolocation data in your photos. Would you like to know about photos from a specific year or time period?"
    }
    
    private func handleAlbumQuery(query: String, keywords: [String]) async -> String {
        let queryLower = query.lowercased()
        
        // Extract temporal context (year, month)
        let targetYear = extractYear(from: query)
        let targetMonth = extractMonth(from: query)
        
        // Check if asking for general album information
        let isGeneralQuery = queryLower.contains("tell me about") || 
                            queryLower.contains("what albums") || 
                            queryLower.contains("list albums") ||
                            queryLower.contains("show albums") ||
                            (queryLower.contains("album") && !queryLower.contains("from") && targetYear == nil)
        
        // Handle temporal album queries: "albums from 2023", "albums in 2023", etc.
        if let year = targetYear {
            var matchingAlbums: [ContentView.AlbumInfo] = []
            
            if let month = targetMonth {
                // Specific month and year
                matchingAlbums = allAlbums.filter { album in
                    // Check if album name contains year and month pattern
                    let albumLower = album.albumName.lowercased()
                    let hasYear = albumLower.contains(String(year)) || albumLower.contains(String(year).suffix(2))
                    let monthName = Calendar.current.monthSymbols[month - 1].lowercased()
                    let monthAbbrev = Calendar.current.shortMonthSymbols[month - 1].lowercased()
                    let hasMonth = albumLower.contains(monthName) || albumLower.contains(monthAbbrev)
                    return hasYear && hasMonth
                }
                
                if !matchingAlbums.isEmpty {
                    let monthName = Calendar.current.monthSymbols[month - 1]
                    let totalItems = matchingAlbums.reduce(0) { $0 + $1.photoCount + $1.videoCount }
                    let totalPhotos = matchingAlbums.reduce(0) { $0 + $1.photoCount }
                    let totalVideos = matchingAlbums.reduce(0) { $0 + $1.videoCount }
                    
                    var response = "In \(monthName) \(year), you have \(matchingAlbums.count) \(matchingAlbums.count == 1 ? "album" : "albums")"
                    if totalItems > 0 {
                        response += " with \(totalItems) total items"
                        if totalPhotos > 0 && totalVideos > 0 {
                            response += " (\(totalPhotos) photos, \(totalVideos) videos)"
                        } else if totalPhotos > 0 {
                            response += " (\(totalPhotos) photos)"
                        } else if totalVideos > 0 {
                            response += " (\(totalVideos) videos)"
                        }
                    }
                    response += ":\n\n"
                    
                    let albumList = matchingAlbums.prefix(10).map { album in
                        var desc = "• \(album.albumName)"
                        if album.photoCount > 0 || album.videoCount > 0 {
                            var counts: [String] = []
                            if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                            if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                            desc += " (\(counts.joined(separator: ", ")))"
                        }
                        if !album.timespan.isEmpty && album.timespan != "—" {
                            desc += " — \(album.timespan)"
                        }
                        return desc
                    }.joined(separator: "\n")
                    
                    response += albumList
                    if matchingAlbums.count > 10 {
                        response += "\n\n...and \(matchingAlbums.count - 10) more albums"
                    }
                    
                    return response
                }
            } else {
                // Just year
                matchingAlbums = allAlbums.filter { album in
                    let albumLower = album.albumName.lowercased()
                    return albumLower.contains(String(year)) || albumLower.contains(String(year).suffix(2))
                }
                
                if !matchingAlbums.isEmpty {
                    let totalItems = matchingAlbums.reduce(0) { $0 + $1.photoCount + $1.videoCount }
                    let totalPhotos = matchingAlbums.reduce(0) { $0 + $1.photoCount }
                    let totalVideos = matchingAlbums.reduce(0) { $0 + $1.videoCount }
                    
                    var response = "In \(year), you have \(matchingAlbums.count) \(matchingAlbums.count == 1 ? "album" : "albums")"
                    if totalItems > 0 {
                        response += " containing \(totalItems) total items"
                        if totalPhotos > 0 && totalVideos > 0 {
                            response += " (\(totalPhotos) photos, \(totalVideos) videos)"
                        } else if totalPhotos > 0 {
                            response += " (\(totalPhotos) photos)"
                        } else if totalVideos > 0 {
                            response += " (\(totalVideos) videos)"
                        }
                    }
                    response += ":\n\n"
                    
                    // Group by month if possible
                    let albumsByMonth = Dictionary(grouping: matchingAlbums) { album in
                        // Try to extract month from album name
                        let albumLower = album.albumName.lowercased()
                        for (index, monthName) in Calendar.current.monthSymbols.enumerated() {
                            if albumLower.contains(monthName.lowercased()) {
                                return index + 1
                            }
                        }
                        return 0 // No month found
                    }
                    
                    if albumsByMonth.count > 1 && albumsByMonth[0] == nil {
                        // We have month groupings
                        let sortedMonths = albumsByMonth.keys.filter { $0 > 0 }.sorted()
                        for month in sortedMonths {
                            if let monthAlbums = albumsByMonth[month] {
                                let monthName = Calendar.current.monthSymbols[month - 1]
                                response += "\(monthName):\n"
                                for album in monthAlbums.prefix(5) {
                                    response += "  • \(album.albumName)"
                                    if album.photoCount > 0 || album.videoCount > 0 {
                                        var counts: [String] = []
                                        if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                                        if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                                        response += " (\(counts.joined(separator: ", ")))"
                                    }
                                    response += "\n"
                                }
                                if monthAlbums.count > 5 {
                                    response += "  ...and \(monthAlbums.count - 5) more\n"
                                }
                            }
                        }
                    } else {
                        // List all albums
                        let albumList = matchingAlbums.prefix(15).map { album in
                            var desc = "• \(album.albumName)"
                            if album.photoCount > 0 || album.videoCount > 0 {
                                var counts: [String] = []
                                if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                                if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                                desc += " (\(counts.joined(separator: ", ")))"
                            }
                            return desc
                        }.joined(separator: "\n")
                        response += albumList
                        if matchingAlbums.count > 15 {
                            response += "\n\n...and \(matchingAlbums.count - 15) more albums"
                        }
                    }
                    
                    return response
                }
            }
        }
        
        // Handle general album queries: "Tell me about my albums", "What albums do I have?"
        if isGeneralQuery {
            let totalAlbums = allAlbums.count
            let totalItems = allAlbums.reduce(0) { $0 + $1.photoCount + $1.videoCount }
            let totalPhotos = allAlbums.reduce(0) { $0 + $1.photoCount }
            let totalVideos = allAlbums.reduce(0) { $0 + $1.videoCount }
            
            let albumYears = Set(allAlbums.compactMap { album in
                extractYear(from: album.albumName)
            })
            let years = Array(albumYears).sorted()
            
            var response = "You have \(totalAlbums) \(totalAlbums == 1 ? "album" : "albums") in your library"
            if totalItems > 0 {
                response += " containing \(totalItems) total items"
                if totalPhotos > 0 && totalVideos > 0 {
                    response += " (\(totalPhotos) photos, \(totalVideos) videos)"
                } else if totalPhotos > 0 {
                    response += " (\(totalPhotos) photos)"
                } else if totalVideos > 0 {
                    response += " (\(totalVideos) videos)"
                }
            }
            
            if !years.isEmpty, let firstYear = years.first, let lastYear = years.last {
                if firstYear != lastYear {
                    response += ", spanning from \(firstYear) to \(lastYear)"
                } else {
                    response += " from \(firstYear)"
                }
            }
            response += ".\n\n"
            
            // Show some example albums
            let sampleAlbums = allAlbums.prefix(10)
            if !sampleAlbums.isEmpty {
                response += "Here are some of your albums:\n"
                for album in sampleAlbums {
                    response += "• \(album.albumName)"
                    if album.photoCount > 0 || album.videoCount > 0 {
                        var counts: [String] = []
                        if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                        if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                        response += " (\(counts.joined(separator: ", ")))"
                    }
                    if !album.timespan.isEmpty && album.timespan != "—" {
                        response += " — \(album.timespan)"
                    }
                    response += "\n"
                }
                if allAlbums.count > 10 {
                    response += "\n...and \(allAlbums.count - 10) more albums. Ask me about a specific year to see more!"
                }
            }
            
            return response
        }
        
        // Fallback: search by name
        let searchTerms = keywords.filter { word in
            !["album", "albums", "from", "in", "the", "my", "what", "tell", "me", "about", "do", "i", "have"].contains(word)
        }
        
        if !searchTerms.isEmpty {
            let searchTerm = searchTerms.joined(separator: " ")
            let matchingAlbums = allAlbums.filter { album in
                album.albumName.localizedCaseInsensitiveContains(searchTerm) ||
                album.folder.localizedCaseInsensitiveContains(searchTerm)
            }
            
            if !matchingAlbums.isEmpty {
                if matchingAlbums.count == 1 {
                    let album = matchingAlbums[0]
                    var response = "Found album '\(album.albumName)'"
                    if album.photoCount > 0 || album.videoCount > 0 {
                        var counts: [String] = []
                        if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                        if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                        response += " with \(counts.joined(separator: " and "))"
                    }
                    if !album.timespan.isEmpty && album.timespan != "—" {
                        response += ". Timespan: \(album.timespan)"
                    }
                    return response + "."
                } else {
                    var response = "Found \(matchingAlbums.count) albums matching '\(searchTerm)':\n\n"
                    let albumList = matchingAlbums.prefix(10).map { album in
                        var desc = "• \(album.albumName)"
                        if album.photoCount > 0 || album.videoCount > 0 {
                            var counts: [String] = []
                            if album.photoCount > 0 { counts.append("\(album.photoCount) photos") }
                            if album.videoCount > 0 { counts.append("\(album.videoCount) videos") }
                            desc += " (\(counts.joined(separator: ", ")))"
                        }
                        return desc
                    }.joined(separator: "\n")
                    response += albumList
                    if matchingAlbums.count > 10 {
                        response += "\n\n...and \(matchingAlbums.count - 10) more"
                    }
                    return response
                }
            }
        }
        
        return "I couldn't find any albums matching your query. Try asking about albums from a specific year (like 'albums from 2023') or check the Database tab to see all your albums."
    }
    
    private func handlePhotoQuery(query: String, keywords: [String]) async -> String {
        // Analyze photos based on query
        // This could use Vision framework to analyze image content
        return "I can help you find photos based on content, location, or time. Try asking specific questions like 'How many photos do I have from 2023?' or 'Show me albums from last year.'"
    }
    
    private func handleGeneralQuery(query: String, keywords: [String]) async -> String {
        // Provide helpful general information with conversational tone
        let totalItemsInAlbums = await countAllMediaInAlbums(albums.map { $0.album })
        let totalItems = totalItemsInAlbums + photosNotInAlbums.photoCount + photosNotInAlbums.videoCount
        let albumYears = Set(albums.map { $0.year })
        let photoYears = Set(allPhotos.map { $0.year })
        let years = Array(albumYears.union(photoYears)).sorted()
        
        var response = "Hi! I'm here to help you explore your photo library. "
        
        if totalItems > 0 {
            response += "You have \(totalItems) total items"
            
            // Add breakdown
            var typeBreakdown: [String] = []
            let totalPhotos = totalItemsInAlbums + photosNotInAlbums.photoCount // Approximate
            let totalVideos = photosNotInAlbums.videoCount // Approximate
            if totalPhotos > 0 { typeBreakdown.append("\(totalPhotos) photos") }
            if totalVideos > 0 { typeBreakdown.append("\(totalVideos) videos") }
            if !typeBreakdown.isEmpty {
                response += " (\(typeBreakdown.joined(separator: ", ")))"
            }
            
            response += " across \(albums.count) \(albums.count == 1 ? "album" : "albums")"
            
            if let firstYear = years.first, let lastYear = years.last, firstYear != lastYear {
                response += ", covering \(years.count) years from \(firstYear) to \(lastYear)"
            } else if let year = years.first {
                response += " from \(year)"
            }
            response += ". "
        } else {
            response += "I don't see any items in your library yet. Make sure you've granted photo library access! "
        }
        
        // Add conversational suggestions
        response += "\n\nI can help you with:\n"
        response += "• Finding out how many items you have (by year, month, or overall)\n"
        response += "• Discovering albums from specific time periods (e.g., 'albums from 2023')\n"
        response += "• Learning about your collection's timeline and organization\n"
        response += "• Searching for specific albums or folders\n"
        response += "• Understanding what's in your library across all media types\n\n"
        response += "Just ask me naturally! For example:\n"
        response += "• \"What albums do I have from 2023?\"\n"
        response += "• \"How many photos do I have?\"\n"
        response += "• \"Tell me about my albums\"\n"
        response += "• \"Show me photos from January 2024\""
        
        return response
    }
    
    private func countPhotosInAlbums(_ albums: [PHAssetCollection]) async -> Int {
        var total = 0
        for album in albums {
            let fetchOptions = PHFetchOptions()
            // Count all media types, not just images
            let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            total += assets.count
        }
        return total
    }
    
    private func countAllMediaInAlbums(_ albums: [PHAssetCollection]) async -> Int {
        var total = 0
        for album in albums {
            let fetchOptions = PHFetchOptions()
            // Count all media types
            let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            total += assets.count
        }
        return total
    }
    
    enum QueryIntent {
        case countQuery
        case temporalQuery
        case locationQuery
        case albumQuery
        case photoQuery
        case general
    }
}


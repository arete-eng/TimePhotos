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
    
    init(albums: [(year: Int, month: Int?, album: PHAssetCollection)], allAlbums: [ContentView.AlbumInfo]) {
        self.albums = albums
        self.allAlbums = allAlbums
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
        let years = Array(Set(albums.map { $0.year })).sorted()
        let yearRange = years.isEmpty ? "unknown" : "\(years.first ?? 0) to \(years.last ?? 0)"
        
        return """
        - Total albums: \(albums.count)
        - Year range: \(yearRange)
        - Years with photos: \(years.count)
        """
    }
    
    private func processQueryWithEnhancedNL(_ query: String) async -> String {
        // Use Natural Language framework to understand the query
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .sentimentScore])
        tagger.string = query.lowercased()
        
        // Extract key terms and intent
        var keywords: [String] = []
        var intent: QueryIntent = .general
        let queryLower = query.lowercased()
        
        // Enhanced intent detection using multiple patterns
        if queryLower.contains("how many") || queryLower.contains("count") || queryLower.contains("total") || queryLower.contains("number of") {
            intent = .countQuery
        } else if queryLower.contains("year") || queryLower.contains("when") || queryLower.contains("date") || queryLower.contains("time") || queryLower.contains("month") {
            intent = .temporalQuery
        } else if queryLower.contains("where") || queryLower.contains("location") || queryLower.contains("place") || queryLower.contains("city") || queryLower.contains("country") {
            intent = .locationQuery
        } else if queryLower.contains("album") || queryLower.contains("folder") || queryLower.contains("collection") {
            intent = .albumQuery
        } else if queryLower.contains("photo") || queryLower.contains("image") || queryLower.contains("picture") || queryLower.contains("photo") {
            intent = .photoQuery
        }
        
        tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word, scheme: .lexicalClass) { _, tokenRange in
            let word = String(query[tokenRange]).lowercased()
            keywords.append(word)
            return true
        }
        
        // Process based on intent with more conversational responses
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
    
    private func handleCountQuery(query: String, keywords: [String]) async -> String {
        // Extract year if mentioned
        var targetYear: Int? = nil
        let queryLower = query.lowercased()
        
        // Look for year in the query
        let yearPattern = #"\b(19|20)\d{2}\b|\b'\d{2}\b"#
        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) {
            if let yearRange = Range(match.range, in: query) {
                let yearStr = String(query[yearRange]).replacingOccurrences(of: "'", with: "")
                if let year = Int(yearStr) {
                    targetYear = year < 100 ? 2000 + year : year
                }
            }
        }
        
        if let year = targetYear {
            let yearAlbums = albums.filter { $0.year == year }
            let totalPhotos = await countPhotosInAlbums(yearAlbums.map { $0.album })
            if totalPhotos > 0 {
                return "In \(year), you captured \(totalPhotos) photos across \(yearAlbums.count) \(yearAlbums.count == 1 ? "album" : "albums"). That's quite a collection from that year!"
            } else {
                return "I don't see any photos from \(year) in your library. Would you like to know about a different year?"
            }
        } else {
            let totalPhotos = await countPhotosInAlbums(albums.map { $0.album })
            let totalAlbums = albums.count
            let years = Array(Set(albums.map { $0.year })).sorted()
            
            if totalPhotos > 0 {
                var response = "Your photo library contains \(totalPhotos) photos across \(totalAlbums) \(totalAlbums == 1 ? "album" : "albums")"
                if let firstYear = years.first, let lastYear = years.last, firstYear != lastYear {
                    response += ", spanning from \(firstYear) to \(lastYear)"
                } else if let year = years.first {
                    response += " from \(year)"
                }
                response += ". That's an impressive collection!"
                return response
            } else {
                return "I don't see any photos in your library yet. Make sure you've granted photo library access!"
            }
        }
    }
    
    private func handleTemporalQuery(query: String, keywords: [String]) async -> String {
        // Extract year or month using Natural Language framework
        var targetYear: Int? = nil
        var targetMonth: Int? = nil
        
        let monthNames = ["january", "february", "march", "april", "may", "june",
                         "july", "august", "september", "october", "november", "december"]
        let monthAbbrevs = ["jan", "feb", "mar", "apr", "may", "jun",
                           "jul", "aug", "sep", "oct", "nov", "dec"]
        
        let queryLower = query.lowercased()
        
        // Extract year - look for 4-digit years or 2-digit years with context
        let yearPattern = #"\b(19|20)\d{2}\b|\b'\d{2}\b"#
        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) {
            if let yearRange = Range(match.range, in: query) {
                let yearStr = String(query[yearRange]).replacingOccurrences(of: "'", with: "")
                if let year = Int(yearStr) {
                    targetYear = year < 100 ? 2000 + year : year
                }
            }
        }
        
        // Extract month
        for (index, monthName) in monthNames.enumerated() {
            if queryLower.contains(monthName) {
                targetMonth = index + 1
                break
            }
        }
        
        if targetMonth == nil {
            for (index, monthAbbrev) in monthAbbrevs.enumerated() {
                if queryLower.contains(monthAbbrev) && queryLower.contains(monthAbbrev + " ") {
                    targetMonth = index + 1
                    break
                }
            }
        }
        
        if let year = targetYear, let month = targetMonth {
            let matchingAlbums = albums.filter { $0.year == year && $0.month == month }
            let photoCount = await countPhotosInAlbums(matchingAlbums.map { $0.album })
            let monthName = Calendar.current.monthSymbols[month - 1]
            return "In \(monthName) \(year), you have \(photoCount) photos across \(matchingAlbums.count) albums."
        } else if let year = targetYear {
            let yearAlbums = albums.filter { $0.year == year }
            let photoCount = await countPhotosInAlbums(yearAlbums.map { $0.album })
            return "In \(year), you have \(photoCount) photos across \(yearAlbums.count) albums."
        } else {
            let years = Array(Set(albums.map { $0.year })).sorted()
            if let firstYear = years.first, let lastYear = years.last {
                return "Your photos span from \(firstYear) to \(lastYear), covering \(years.count) years."
            }
            return "I can help you find photos from specific years or months. Try asking about a particular year or month!"
        }
    }
    
    private func handleLocationQuery(query: String, keywords: [String]) async -> String {
        // This would require location data from photos
        // For now, provide a general response
        return "I can see you have photos with location data. To get specific location information, I'd need to analyze the geolocation data in your photos. Would you like to know about photos from a specific year or time period?"
    }
    
    private func handleAlbumQuery(query: String, keywords: [String]) async -> String {
        // Search for albums matching keywords
        let searchTerm = keywords.joined(separator: " ")
        let matchingAlbums = allAlbums.filter { album in
            album.albumName.localizedCaseInsensitiveContains(searchTerm) ||
            album.folder.localizedCaseInsensitiveContains(searchTerm)
        }
        
        if matchingAlbums.isEmpty {
            return "I couldn't find any albums matching '\(searchTerm)'. Try asking about a specific year or month, or check the Database tab to see all your albums."
        } else if matchingAlbums.count == 1 {
            let album = matchingAlbums[0]
            return "Found album '\(album.albumName)' with \(album.photoCount) photos and \(album.videoCount) videos. Timespan: \(album.timespan)."
        } else {
            let albumList = matchingAlbums.prefix(5).map { "\($0.albumName) (\($0.photoCount) photos)" }.joined(separator: ", ")
            return "Found \(matchingAlbums.count) albums matching '\(searchTerm)': \(albumList)\(matchingAlbums.count > 5 ? "..." : "")"
        }
    }
    
    private func handlePhotoQuery(query: String, keywords: [String]) async -> String {
        // Analyze photos based on query
        // This could use Vision framework to analyze image content
        return "I can help you find photos based on content, location, or time. Try asking specific questions like 'How many photos do I have from 2023?' or 'Show me albums from last year.'"
    }
    
    private func handleGeneralQuery(query: String, keywords: [String]) async -> String {
        // Provide helpful general information with conversational tone
        let totalPhotos = await countPhotosInAlbums(albums.map { $0.album })
        let years = Array(Set(albums.map { $0.year })).sorted()
        
        // Analyze sentiment of query to respond appropriately
        let sentimentTagger = NLTagger(tagSchemes: [.sentimentScore])
        sentimentTagger.string = query
        var sentiment: Double = 0.0
        sentimentTagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag = tag {
                // Extract sentiment score from tag
                sentiment = tag.rawValue.contains("positive") ? 0.5 : (tag.rawValue.contains("negative") ? -0.5 : 0.0)
            }
            return true
        }
        
        var response = "Hi! I'm here to help you explore your photo library. "
        
        if totalPhotos > 0 {
            response += "You have \(totalPhotos) photos across \(albums.count) \(albums.count == 1 ? "album" : "albums")"
            if let firstYear = years.first, let lastYear = years.last, firstYear != lastYear {
                response += ", covering \(years.count) years from \(firstYear) to \(lastYear)"
            } else if let year = years.first {
                response += " from \(year)"
            }
            response += ". "
        } else {
            response += "I don't see any photos in your library yet. "
        }
        
        // Add conversational suggestions based on what they might want to know
        response += "\n\nI can help you with things like:\n"
        response += "• Finding out how many photos you have (by year or overall)\n"
        response += "• Discovering albums from specific time periods\n"
        response += "• Learning about your photo collection's timeline\n"
        response += "• Searching for specific albums or folders\n\n"
        response += "Just ask me naturally, like \"How many photos do I have from 2023?\" or \"Tell me about my albums.\""
        
        return response
    }
    
    private func countPhotosInAlbums(_ albums: [PHAssetCollection]) async -> Int {
        var total = 0
        for album in albums {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
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


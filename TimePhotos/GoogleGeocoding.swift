//
//  GoogleGeocoding.swift
//  TimePhotos
//
//  Created for TimePhotos App.
//

import Foundation
import CoreLocation

struct GoogleGeocodingService {
    // REPLACE THIS WITH YOUR ACTUAL API KEY
    static let apiKey = "AIzaSyAnmuQwdb9BYPCv48bkDPuGgeXseuNcWAE"
    
    static func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String? {
        // If no API key is set, return nil
        guard !apiKey.isEmpty, apiKey != "YOUR_GOOGLE_MAPS_API_KEY_HERE" else {
            print("⚠️ Google Maps API Key not set in GoogleGeocoding.swift")
            return nil
        }
        
        let urlString = "https://maps.googleapis.com/maps/api/geocode/json?latlng=\(coordinate.latitude),\(coordinate.longitude)&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        // Use async/await URLSession
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Use JSONSerialization as requested by user example
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let results = json["results"] as? [[String: Any]], let first = results.first {
                if let addressComponents = first["address_components"] as? [[String: Any]] {
                    
                    // Extract desired components (example: town, state, country, postal code)
                    var town: String?
                    var state: String?
                    var country: String?
                    var postalCode: String?
                    
                    for component in addressComponents {
                        if let types = component["types"] as? [String], let longName = component["long_name"] as? String {
                            
                            if types.contains("locality") {
                                town = longName
                            }
                            
                            if types.contains("administrative_area_level_1") {
                                state = longName
                            }
                            
                            if types.contains("country") {
                                country = longName
                            }
                            
                            if types.contains("postal_code") {
                                postalCode = longName
                            }
                        }
                    }
                    
                    let address = [town, state, country, postalCode].compactMap({ $0 }).joined(separator: ", ")
                    if !address.isEmpty {
                        return address
                    }
                }
            }
        }
        
        return nil
    }
}

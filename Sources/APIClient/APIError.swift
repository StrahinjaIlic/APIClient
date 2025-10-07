//
//  File.swift
//  APIClient
//
//  Created by Strahinja Ilic on 7. 10. 2025..
//

import Foundation

public enum APIError: Error, LocalizedError {
    case invalidResponse
    case decodingError(Error)
    case networkError(Error)
    case custom(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "🛑 The server returned an invalid response."
        case .decodingError(let error):
            return "🧩 Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "🌐 Network error occurred: \(error.localizedDescription)"
        case .custom(let message):
            return "✉️ \(message)"
        }
    }
}

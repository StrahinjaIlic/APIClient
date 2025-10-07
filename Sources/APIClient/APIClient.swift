// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation
import XCTest

// MARK: - APIClient

public struct APIClient {
    let baseURL: URL
    let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.session = .shared
    }

    public init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func performRequest<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw APIError.invalidResponse
            }

            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
}

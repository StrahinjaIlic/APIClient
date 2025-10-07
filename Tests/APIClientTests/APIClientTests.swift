// MARK: - APIClient.swift

import Foundation

// MARK: - Network Session Protocol (Dependency Injection)

public protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkSession {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

// MARK: - API Error

public enum APIError: Error, LocalizedError, Equatable {
    case invalidResponse(statusCode: Int)
    case decodingError(String)
    case networkError(String)
    case invalidURL
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let statusCode):
            return "🛑 Invalid response with status code: \(statusCode)"
        case .decodingError(let message):
            return "🧩 Decoding failed: \(message)"
        case .networkError(let message):
            return "🌐 Network error: \(message)"
        case .invalidURL:
            return "🔗 Invalid URL"
        }
    }
    
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse(let l), .invalidResponse(let r)):
            return l == r
        case (.decodingError(let l), .decodingError(let r)):
            return l == r
        case (.networkError(let l), .networkError(let r)):
            return l == r
        case (.invalidURL, .invalidURL):
            return true
        default:
            return false
        }
    }
}

// MARK: - API Client

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: NetworkSession
    private let decoder: JSONDecoder
    
    public init(
        baseURL: URL,
        session: NetworkSession = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }
    
    public func performRequest<T: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        
        // Set headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: 0)
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - HTTP Method

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// MARK: - APIClientTests.swift

import XCTest
@testable import APIClient

// MARK: - Test Models

struct User: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let isPremium: Bool
}

// MARK: - Mock Network Session (Actor for thread-safety)

actor MockNetworkSession: NetworkSession {
    private var responses: [String: Result<(Data, URLResponse), Error>] = [:]
    
    func setResponse(
        for path: String,
        statusCode: Int = 200,
        data: Data = Data()
    ) {
        let url = URL(string: "https://mockapi.example.com")!.appendingPathComponent(path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        responses[path] = .success((data, response))
    }
    
    func setError(for path: String, error: Error) {
        responses[path] = .failure(error)
    }
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let path = request.url?.lastPathComponent,
              let result = responses[path] else {
            throw URLError(.badURL)
        }
        
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
    
    func reset() {
        responses.removeAll()
    }
}

// MARK: - Tests

final class APIClientTests: XCTestCase {
    var client: APIClient!
    var mockSession: MockNetworkSession!
    
    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        client = APIClient(
            baseURL: URL(string: "https://mockapi.example.com")!,
            session: mockSession
        )
    }
    
    override func tearDown() async throws {
        await mockSession.reset()
        client = nil
        mockSession = nil
        try await super.tearDown()
    }
    
    // MARK: - Success Tests
    
    func testPerformRequest_returnsDecodable() async throws {
        // Given
        let mockJSON = """
        { "id": 1, "name": "Steve Jobs", "isPremium": true }
        """.data(using: .utf8)!
        
        await mockSession.setResponse(
            for: "user/1",
            statusCode: 200,
            data: mockJSON
        )
        
        // When
        let user: User = try await client.performRequest(path: "user/1")
        
        // Then
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.name, "Steve Jobs")
        XCTAssertTrue(user.isPremium)
    }
    
    // MARK: - Error Tests
    
    func testPerformRequest_invalidResponse_throws() async throws {
        // Given
        await mockSession.setResponse(
            for: "user/1",
            statusCode: 404,
            data: Data()
        )
        
        // When/Then
        do {
            let _: User = try await client.performRequest(path: "user/1")
            XCTFail("Expected invalidResponse error")
        } catch let error as APIError {
            if case .invalidResponse(let statusCode) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected invalidResponse error, got: \(error)")
            }
        }
    }
    
    func testPerformRequest_decodingError_throws() async throws {
        // Given - Missing required field 'isPremium'
        let invalidJSON = """
        { "id": 1, "name": "Steve Jobs" }
        """.data(using: .utf8)!
        
        await mockSession.setResponse(
            for: "user/1",
            statusCode: 200,
            data: invalidJSON
        )
        
        // When/Then
        do {
            let _: User = try await client.performRequest(path: "user/1")
            XCTFail("Expected decodingError")
        } catch let error as APIError {
            if case .decodingError = error {
                // Success - expected error
            } else {
                XCTFail("Expected decodingError, got: \(error)")
            }
        }
    }
    
    func testPerformRequest_networkError_throws() async throws {
        // Given
        await mockSession.setError(
            for: "user/1",
            error: URLError(.notConnectedToInternet)
        )
        
        // When/Then
        do {
            let _: User = try await client.performRequest(path: "user/1")
            XCTFail("Expected networkError")
        } catch let error as APIError {
            if case .networkError(let message) = error {
                XCTAssertTrue(message.contains("Internet") || message.contains("connection"))
            } else {
                XCTFail("Expected networkError, got: \(error)")
            }
        }
    }
    
    // MARK: - Additional Tests
    
    func testPerformRequest_withCustomHeaders() async throws {
        // Given
        let mockJSON = """
        { "id": 2, "name": "Tim Cook", "isPremium": false }
        """.data(using: .utf8)!
        
        await mockSession.setResponse(
            for: "user/2",
            statusCode: 200,
            data: mockJSON
        )
        
        // When
        let user: User = try await client.performRequest(
            path: "user/2",
            headers: ["Authorization": "Bearer token123"]
        )
        
        // Then
        XCTAssertEqual(user.name, "Tim Cook")
        XCTAssertFalse(user.isPremium)
    }
    
    func testPerformRequest_withDifferentStatusCodes() async throws {
        // Test 201 Created
        let mockJSON = """
        { "id": 3, "name": "Craig Federighi", "isPremium": true }
        """.data(using: .utf8)!
        
        await mockSession.setResponse(
            for: "user/3",
            statusCode: 201,
            data: mockJSON
        )
        
        let user: User = try await client.performRequest(path: "user/3")
        XCTAssertEqual(user.id, 3)
    }
    
    func testPerformRequest_serverError_throws() async throws {
        // Given - 500 Internal Server Error
        await mockSession.setResponse(
            for: "user/1",
            statusCode: 500,
            data: Data()
        )
        
        // When/Then
        do {
            let _: User = try await client.performRequest(path: "user/1")
            XCTFail("Expected invalidResponse error")
        } catch let error as APIError {
            if case .invalidResponse(let statusCode) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected invalidResponse with 500, got: \(error)")
            }
        }
    }
}

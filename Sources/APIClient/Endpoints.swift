//
//  Endpoints.swift
//  APIClient
//
//  Created by Strahinja Ilic on 7. 10. 2025..
//

public enum Endpoint {
    case register(email: String, password: String)
    case login(email: String, password: String)
    case user(id: Int)

    public var path: String {
        switch self {
        case .register: return "/api/register"
        case .login: return "/api/login"
        case .user(let id): return "/api/users/\(id)"
        }
    }

    public var method: String {
        switch self {
        case .register, .login:
            return "POST"
        case .user:
            return "GET"
        }
    }

    public var body: [String: Any]? {
        switch self {
        case let .register(email, password),
             let .login(email, password):
            return ["email": email, "password": password]
        case .user:
            return nil
        }
    }
}

//
//  Network.swift
//  WordZap
//
//  Created by Barak Ben Hur on 18/10/2024.
//



import Foundation

protocol DataSource: ObservableObject {}

internal enum APIRoute: String { case root = "", word, score, gender, changeLanguage, getPremiumScore, getAllPremiumScores, scoreboard, place, getScore, getWord, addGuess, premiumScore, isLoggedin, aiGuess, aiHealth = "health" }

// MARK: Networkble
private protocol Networkble: DataSource {
    typealias UrlPathMaker = (APIRoute) -> String
    
    var responedQueue: DispatchQueue { get }
    var root: String { get }
    var url: UrlPathMaker { get }
}

// MARK: NetworkError
private enum NetworkError: Error {
    case badUrl
    case invalidRequestBody
    case badResponse
    case badStatus
    case noData
    case failedToDecodeResponse
    case custom(error: Error)
}

// MARK: HttpMethod
internal enum HttpMethod: String {
    case post = "POST", get = "GET"
}

// MARK: Network
class Network: Networkble {
    enum APIRoot: String { case login, score, words, ai, pvp }
    static private var base: String = ""
    
    var baseURL: String {
#if DEBUG
        return Network.base
#else
        return Network.base
#endif
    }
    
    // MARK: responedQueue
    fileprivate let responedQueue: DispatchQueue = DispatchQueue.main
    
    // MARK: root - root url value
    fileprivate let root: String
    
    // MARK: path - path url value
    fileprivate var url: UrlPathMaker {
        return { [weak self] url in
            guard let self else { return "" }
            return "\(root)/\(url.rawValue)"
        }
    }
    
    // MARK: init
    //    "http://localhost:3000"
    //    "https://word-attack-server.onrender.com"
    internal init(root: APIRoot, base: String = "http://localhost:3000") {
        self.root = root.rawValue
        Network.base = base
    }
    
    enum DeviceTokenService {
        static var apiBase: String {
            // Point to your Node server (https + real host in production)
            // e.g., "https://word-attack-server.onrender.com"
            return BaseUrl.value
        }
        
        static func register(uniqe: String? ,token: String, environment: String, userId: String?) async {
            guard let uniqe else { return }
            guard let url = URL(string: "\(apiBase)/devices/register") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "token": token,
                "uniqe": uniqe,
                "environment": environment,   // "sandbox" or "prod"
                "bundleId": "com.barak.wordzap",
                "userId": userId ?? ""
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                _ = try await URLSession.shared.data(for: req)
            } catch {
                print("Device token register failed:", error)
            }
        }
    }
    
    // MARK: send - to network
    /// - Parameters:
    ///  - method
    ///  - url
    ///  - parameters
    ///  - complition
    ///  - error
    private func send<T: Codable>(request: URLRequest) async -> Result<T, NetworkError> {
        return await withCheckedContinuation({ c in
                URLSession.shared.dataTask(with: request) { data, response, err in
                    guard let err else {
                        do {
                            guard let response = response as? HTTPURLResponse else { throw NetworkError.badResponse }
                            guard response.statusCode >= 200 && response.statusCode < 300 else { throw NetworkError.badStatus }
                            guard let data else { throw NetworkError.noData }
                            guard let decodedResponse = try? JSONDecoder().decode(T.self, from: data) else { throw NetworkError.failedToDecodeResponse }
                            
                            // return result
                            return c.resume(returning: .success(decodedResponse))
                            
                            // handele expetions
                        } catch let err { return c.resume(returning: .failure(.custom(error: err))) }
                    }
                    
                    // return error
                    c.resume(returning: .failure(.custom(error: err)))
                    
                }.resume()
        })
    }
}

// MARK: Network internal extension
extension Network {
    // MARK: send - call send to network and unwrap (result || error)
    /// - Parameters:
    ///  - method
    ///  - url
    ///  - parameters
    ///  - complition
    ///  - error
    internal func send<T: Codable>(method: HttpMethod = .post, route: APIRoute, parameters: [String: Any] = [:]) async -> T? {
        let url = url(route)
        do {
            let request = try Request(method: method, url: url, parameters: parameters).build()
            let result: Result<T, NetworkError> = await send(request: request)
            
            switch result {
            case .success(let success):
                return success
            case .failure(let failure):
                print(failure)
                return nil
            }
        } catch { print(error.localizedDescription); return nil }
    }
    
    // MARK: send - call send to network and unwrap (result || error)
    /// - Parameters: data
    ///  - method
    ///  - url
    ///  - parameters
    ///  - complition
    ///  - error
    internal func send<T: Codable>(method: HttpMethod = .post, route: APIRoute, parameters: Data) async -> T? {
        let url = url(route)
        do {
            let request = try Request(method: method, url: url).buildWith(parameters)
            let result: Result<T, NetworkError> = await send(request: request)
            
            switch result {
            case .success(let success):
                return success
            case .failure(let failure):
                print(failure)
                return nil
            }
        } catch { print(error.localizedDescription); return nil }
    }
    
    // MARK: ComplitionHandeler
    internal class ComplitionHandeler: ObservableObject {
        func makeValid<T: Codable>(_ complition: @escaping () -> ()) -> (T) -> () { return { _ in complition() } }
        func makeValid<T: Codable>(_ complition: @escaping (T) -> ()) -> (T) -> () { return complition }
    }
    
    // MARK: ParameterHndeler
    internal class ParameterHndeler: ObservableObject {
        // MARK: toDict
        /// - Parameter values
        func toDict(values: DictionaryRepresentable...) -> [String: Any] {
            var dict: [String: Any] = [:]
            values.forEach { dict.merge(dict: $0.dictionary()) }
            return dict
        }
    }
}

// MARK: Network private extension
extension Network {
    // MARK: BaseUrl
    private struct BaseUrl {
        static var value: String {
            get {
#if DEBUG
//              return "http://localhost:3000"
                return Network.base
#else
                return Network.base
#endif
            }
        }
    }
    
    // MARK: Request
    private struct Request {
        private var base: String { get { return BaseUrl.value } }
        
        let method: HttpMethod
        let url: String
        var parameters: [String: Any] = [:]
        
        // MARK: build
        var build: () throws -> URLRequest { newRequest }
        var buildWith: (_ data: Data) throws -> URLRequest { newRequestWith }
        
        // MARK: Private
        private func newRequest() throws -> URLRequest {
            return try createRequestWithType()
                .withHttpMethod(method.rawValue)
                .withHeaders(.init(value: "application/json", headerField: "Content-Type"),
                             .init(value: "application/json", headerField: "Accept"))
        }
        
        private func newRequestWith(httpBody: Data) throws -> URLRequest {
            return try createRequest()
                .withHttpBody(httpBody)
                .withHttpMethod(method.rawValue)
                .withHeaders(.init(value: "application/json", headerField: "Content-Type"),
                             .init(value: "application/json", headerField: "Accept"))
        }
        
        // createRequestWithType -> throws
        private func createRequestWithType() throws -> URLRequest {
            switch method {
            case .post:
                guard let httpBody = parameters.httpBody() else { throw NetworkError.invalidRequestBody }
                return try createRequest().withHttpBody(httpBody)
            case .get:
                return try createRequest()
            }
        }
        
        // createRequest -> throws
        private func createRequest() throws -> URLRequest {
            return URLRequest(url: try createUrl())
        }
        
        // createUrl -> throws
        private func createUrl() throws -> URL {
            guard let url = URL(string: createUrlString()) else { throw NetworkError.badUrl }
            return url
        }
        
        // createUrlString
        private func createUrlString() -> String {
            switch method {
            case .post:
                return "\(base)/\(url)"
            case .get:
                let prametrersFormatted = parameters.requestFormatted()
                let keyValue = prametrersFormatted.isEmpty ? "" : "?\(prametrersFormatted)"
                let urlString = "\(url)\(keyValue)"
                return "\(base)/\(urlString)"
            }
        }
    }
}

// MARK: NetworkError private extension
extension NetworkError: LocalizedError {
    fileprivate var errorDescription: String? {
        switch self {
        case .badUrl: return "There was an error creating the URL"
        case .invalidRequestBody: return "There was an error creating the request body"
        case .badResponse: return "Did not get a valid response"
        case .badStatus: return "Did not get a 2xx status code from the response"
        case .noData: return "No data"
        case .failedToDecodeResponse: return "Failed to decode response into the given type"
        case .custom(error: let error): return error.localizedDescription
        }
    }
}

extension Dictionary {
    func httpBody() -> Data? {
        return try? JSONSerialization.data(withJSONObject: self, options: [])
    }
    
    func requestFormatted() -> String {
        map { key, value in
            let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            return escapedKey + "=" + escapedValue
        }
        .joined(separator: "&")
    }
    
    @discardableResult mutating func merge(dict: [Key: Value]) -> Dictionary<Key, Value> {
        for (k, v) in dict { updateValue(v, forKey: k) }
        return self
    }
}

protocol DictionaryRepresentable {
    func dictionary() -> [String: Any]
}

extension DictionaryRepresentable {
    func dictionary() -> [String: Any] {
        let mirror = Mirror(reflecting: self)
        
        var dict: [String: Any] = [:]
        
        for (_, child) in mirror.children.enumerated() {
            if let label = child.label {
                dict[label] = child.value
            }
        }
        
        return dict
    }
}

struct Haeder {
    let value: String
    let headerField: String
}

extension URLRequest {
    @discardableResult func withHeaders(_ values: Haeder...) -> URLRequest {
        var request = self
        values.forEach { request.setValue($0.value, forHTTPHeaderField: $0.headerField) }
        return request
    }
    
    @discardableResult func withHttpMethod(_ method: String) -> URLRequest {
        var request = self
        request.httpMethod = method
        return request
    }
    
    @discardableResult func withHttpBody(_ body: Data) -> URLRequest {
        var request = self
        request.httpBody = body
        return request
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed: CharacterSet = .urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
}

struct EmptyModel: Codable {}

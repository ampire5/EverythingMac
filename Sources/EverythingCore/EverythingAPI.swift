import Foundation

public struct SearchSort: Codable, Equatable, Sendable {
    public var field: String
    public var ascending: Bool
    public init(field: String = "name", ascending: Bool = true) { self.field = field; self.ascending = ascending }
}
public enum SearchFailure: LocalizedError, Equatable {
    case invalidServer, unauthorized, http(Int), invalidResponse, unavailable, redirected
    public var errorDescription: String? {
        switch self {
        case .invalidServer: return "Укажите адрес HTTP или HTTPS без пароля и параметров запроса."
        case .unauthorized: return "Сервер отклонил авторизацию. Проверьте логин и пароль в настройках."
        case .http(let code): return "Сервер вернул ошибку HTTP \(code)."
        case .invalidResponse: return "Ответ сервера не похож на JSON Everything. Проверьте адрес и HTTP API."
        case .unavailable: return "Сервер недоступен. Проверьте подключение к сети и запущен ли Everything на PC."
        case .redirected: return "Сервер перенаправляет запрос. Укажите конечный адрес в настройках."
        }
    }
}
public final class EverythingAPI: Sendable {
    public static let pageSize = 200
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: RedirectDelegate(), delegateQueue: nil)
    }
    public static func request(server: String, login: String, password: String, query: String, sort: SearchSort, offset: Int) throws -> URLRequest {
        guard var c = URLComponents(string: server), ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { throw SearchFailure.invalidServer }
        let fields = ["name", "path", "size", "date_modified"]
        guard fields.contains(sort.field), offset >= 0 else { throw SearchFailure.invalidServer }
        c.queryItems = [URLQueryItem(name: "search", value: query), URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "count", value: String(pageSize)), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sort", value: sort.field), URLQueryItem(name: "ascending", value: sort.ascending ? "1" : "0"),
            URLQueryItem(name: "path_column", value: "1"), URLQueryItem(name: "size_column", value: "1"), URLQueryItem(name: "date_modified_column", value: "1")]
        // Everything parses form-style query strings, where a literal plus means space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c.url else { throw SearchFailure.invalidServer }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Basic " + Data((login + ":" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    public static func decode(_ data: Data, status: Int) throws -> SearchPage {
        if status == 401 || status == 403 { throw SearchFailure.unauthorized }
        if (300..<400).contains(status) { throw SearchFailure.redirected }
        guard (200..<300).contains(status) else { throw SearchFailure.http(status) }
        do { return try JSONDecoder().decode(SearchPage.self, from: data) }
        catch { throw SearchFailure.invalidResponse }
    }
    public func search(server: String, login: String, password: String, query: String, sort: SearchSort, offset: Int) async throws -> SearchPage {
        let request = try Self.request(server: server, login: login, password: password, query: query, sort: sort, offset: offset)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw SearchFailure.invalidResponse }
            return try Self.decode(data, status: response.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch let error as SearchFailure { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw SearchFailure.unavailable }
    }
    // Stateless delegate: URLSession can call it from its own delegate queue.
    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // Never send saved credentials to a redirect destination.
        }
    }
}

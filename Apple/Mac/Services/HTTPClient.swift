import Foundation
import Combine

/// Injection point for network access: the price and FX services depend only on this; tests inject an in-memory client.
protocol HTTPClient {
    func dataPublisher(for request: URLRequest) -> AnyPublisher<(data: Data, response: URLResponse), URLError>
}

extension URLSession: HTTPClient {
    func dataPublisher(for request: URLRequest) -> AnyPublisher<(data: Data, response: URLResponse), URLError> {
        dataTaskPublisher(for: request).eraseToAnyPublisher()
    }
}

extension URLSession {
    /// Prices and FX rates. The shared session keeps responses in its disk cache (e.g. Bybit's full ticker list,
    /// which sends no cache headers); live data must never be stored there or served from it.
    static let liveData: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

extension URLRequest {
    /// GET for live data that skips any local cache, also when an injected client has one.
    static func liveData(_ url: URL, timeout: TimeInterval = Constants.API.requestTimeout) -> URLRequest {
        URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    }
}

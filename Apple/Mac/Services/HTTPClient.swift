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

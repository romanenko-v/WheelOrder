//
//  OzonHTTP.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

final class OzonHTTP {
    private let base = URL(string: "https://api-seller.ozon.ru")!
    private let clientId: String
    private let apiKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(clientId: String, apiKey: String) {
        self.clientId = clientId
        self.apiKey   = apiKey
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, as: T.Type) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId, forHTTPHeaderField: "Client-Id")
        req.setValue(apiKey,   forHTTPHeaderField: "Api-Key")
        req.httpBody = try encoder.encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "HTTP",
                          code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return try decoder.decode(T.self, from: data)
    }

    func postVoid<B: Encodable>(_ path: String, body: B) async throws {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId, forHTTPHeaderField: "Client-Id")
        req.setValue(apiKey,   forHTTPHeaderField: "Api-Key")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "HTTP",
                          code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "non-2xx"])
        }
    }
}

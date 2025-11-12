//
//  LinuxAsyncURLSession.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = self.dataTask(with: request) { data, resp, err in
                if let err = err {
                    cont.resume(throwing: err); return
                }
                guard let resp = resp else {
                    cont.resume(throwing: URLError(.badServerResponse)); return
                }
                cont.resume(returning: (data ?? Data(), resp))
            }
            task.resume()
        }
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = self.dataTask(with: url) { data, resp, err in
                if let err = err {
                    cont.resume(throwing: err); return
                }
                guard let resp = resp else {
                    cont.resume(throwing: URLError(.badServerResponse)); return
                }
                cont.resume(returning: (data ?? Data(), resp))
            }
            task.resume()
        }
    }
}

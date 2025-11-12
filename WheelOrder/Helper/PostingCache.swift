//
//  PostingCache.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

final class PostingCache {
    private let url: URL
    private var map: [String: Date] = [:]
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(filename: String = "processed_postings.json") {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.url = cwd.appendingPathComponent(filename)
        load()
        pruneOlderThan(hours: 24)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        var tmp: [String: Date] = [:]
        for (k, v) in obj {
            if let d = iso.date(from: v) { tmp[k] = d }
        }
        map = tmp
    }

    private func save() {
        let obj = map.mapValues { iso.string(from: $0) }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }

    func contains(_ posting: String) -> Bool { map.keys.contains(posting) }

    func insert(_ posting: String, at date: Date = Date()) {
        map[posting] = date
        save()
    }

    func remove(_ posting: String) {
        map.removeValue(forKey: posting)
        save()
    }

    func clear() {
        map.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    func pruneOlderThan(hours: Int) {
        let threshold = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        map = map.filter { _, ts in ts >= threshold }
        save()
    }
}

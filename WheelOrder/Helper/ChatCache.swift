//
//  ChatCache.swift
//  WheelOrder
//
//  Created by Вячеслав on 24.11.2025.
//

import Foundation

final class ChatCache {
    private let url: URL
    private var map: [String: Date] = [:]

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let shared: ChatCache = .init()

    private init(filename: String = "processed_chats.json") {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.url = cwd.appendingPathComponent(filename)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }

        var tmp: [String: Date] = [:]
        for (k, v) in obj {
            if let d = iso.date(from: v) {
                tmp[k] = d
            }
        }
        map = tmp
    }

    private func save() {
        let obj = map.mapValues { iso.string(from: $0) }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }

    func contains(_ chatId: String) -> Bool {
        map.keys.contains(chatId)
    }

    func insert(_ chatId: String, at date: Date = Date()) {
        map[chatId] = date
        save()
    }

    func remove(_ chatId: String) {
        map.removeValue(forKey: chatId)
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

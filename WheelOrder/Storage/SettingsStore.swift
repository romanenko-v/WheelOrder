//
//  SettingsStore.swift
//  WheelOrder
//
//  Created by Вячеслав on 22.11.2025.
//

import Foundation

actor SettingsStore {

    struct DataModel: Codable {
        var password: String
        var messageTemplate: String   
        var secondMessageTemplate: String
        var sendMessages: Bool
        var sendSecondMessage: Bool
        var logChatIds: [Int64]?
    }

    static let shared = SettingsStore()

    private let url: URL
    private var data: DataModel

    private init(filename: String = "bot_settings.json") {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.url = cwd.appendingPathComponent(filename)

        if
            let raw = try? Foundation.Data(contentsOf: url),
            var decoded = try? JSONDecoder().decode(DataModel.self, from: raw)
        {
            if decoded.logChatIds == nil { decoded.logChatIds = [] }
            self.data = decoded
            saveSync()
        } else {
            self.data = DataModel(
                password: "123321",
                messageTemplate: Config.MESSAGE_TEXT,
                secondMessageTemplate: "Второе сообщение по умолчанию.",
                sendMessages: true,
                sendSecondMessage: false,
                logChatIds: []
            )
            saveSync()
        }
    }

    private func saveSync() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url)
        }
    }

    private func save() { saveSync() }

    func snapshot() -> DataModel { data }

    func setPassword(_ new: String) {
        data.password = new
        save()
    }

    func setMessageTemplate(_ text: String) {
        data.messageTemplate = text
        save()
    }

    func setSecondMessageTemplate(_ text: String) {
        data.secondMessageTemplate = text
        save()
    }

    @discardableResult
    func toggleSendMessages() -> Bool {
        data.sendMessages.toggle()
        save()
        return data.sendMessages
    }

    @discardableResult
    func toggleSendSecondMessage() -> Bool {
        data.sendSecondMessage.toggle()
        save()
        return data.sendSecondMessage
    }

    @discardableResult
    func toggleLogs(forChat chatId: Int64) -> Bool {
        var ids = Set(data.logChatIds ?? [])
        if ids.contains(chatId) { ids.remove(chatId) }
        else { ids.insert(chatId) }
        data.logChatIds = Array(ids)
        save()
        return ids.contains(chatId)
    }

    func allLogChats() -> [Int64] {
        Array(Set(data.logChatIds ?? []))
    }
}

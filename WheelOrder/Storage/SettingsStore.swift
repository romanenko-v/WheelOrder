//
//  SettingsStore.swift
//  WheelOrder
//
//  Created by Вячеслав on 22.11.2025.
//

import Foundation

actor SettingsStore {
    static let defaultSecondMessageDelayHours = 18
    static let minSecondMessageDelayHours = 1
    static let maxSecondMessageDelayHours = 720

    struct DataModel: Codable {
        var password: String
        var messageTemplate: String   
        var secondMessageTemplate: String
        var sendMessages: Bool
        var sendSecondMessage: Bool
        var secondMessageDelayHours: Int
        var logChatIds: [Int64]?

        init(
            password: String,
            messageTemplate: String,
            secondMessageTemplate: String,
            sendMessages: Bool,
            sendSecondMessage: Bool,
            secondMessageDelayHours: Int = SettingsStore.defaultSecondMessageDelayHours,
            logChatIds: [Int64]?
        ) {
            self.password = password
            self.messageTemplate = messageTemplate
            self.secondMessageTemplate = secondMessageTemplate
            self.sendMessages = sendMessages
            self.sendSecondMessage = sendSecondMessage
            self.secondMessageDelayHours = SettingsStore.normalizedSecondMessageDelayHours(secondMessageDelayHours)
            self.logChatIds = logChatIds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.password = try container.decode(String.self, forKey: .password)
            self.messageTemplate = try container.decode(String.self, forKey: .messageTemplate)
            self.secondMessageTemplate = try container.decode(String.self, forKey: .secondMessageTemplate)
            self.sendMessages = try container.decode(Bool.self, forKey: .sendMessages)
            self.sendSecondMessage = try container.decode(Bool.self, forKey: .sendSecondMessage)
            let delayHours = try container.decodeIfPresent(Int.self, forKey: .secondMessageDelayHours)
                ?? SettingsStore.defaultSecondMessageDelayHours
            self.secondMessageDelayHours = SettingsStore.normalizedSecondMessageDelayHours(delayHours)
            self.logChatIds = try container.decodeIfPresent([Int64].self, forKey: .logChatIds) ?? []
        }
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
            decoded.secondMessageDelayHours = Self.normalizedSecondMessageDelayHours(decoded.secondMessageDelayHours)
            self.data = decoded
            Self.saveSync(data: self.data, to: self.url)
        } else {
            self.data = DataModel(
                password: "123321",
                messageTemplate: Config.MESSAGE_TEXT,
                secondMessageTemplate: "Второе сообщение по умолчанию.",
                sendMessages: true,
                sendSecondMessage: false,
                secondMessageDelayHours: Self.defaultSecondMessageDelayHours,
                logChatIds: []
            )
            Self.saveSync(data: self.data, to: self.url)
        }
    }

    private static func saveSync(data: DataModel, to url: URL) {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url)
        }
    }

    private func saveSync() {
        Self.saveSync(data: data, to: url)
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

    func setSecondMessageDelayHours(_ hours: Int) {
        data.secondMessageDelayHours = Self.normalizedSecondMessageDelayHours(hours)
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

    private static func normalizedSecondMessageDelayHours(_ hours: Int) -> Int {
        min(max(hours, minSecondMessageDelayHours), maxSecondMessageDelayHours)
    }
}

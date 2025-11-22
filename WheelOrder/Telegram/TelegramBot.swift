//
//  TelegramBot.swift
//  WheelOrder
//
//  Created by Vyacheslav on 22.11.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TelegramBot {
    private let token: String
    private let settings: SettingsStore
    private let baseURL: URL

    private var authorizedChats = Set<Int64>()

    private enum ChatState {
        case idle

        case waitingNewMessage1
        case confirmNewMessage1(String)

        case waitingNewMessage2
        case confirmNewMessage2(String)

        case waitingNewPassword
        case confirmNewPassword(String)
    }

    private var states: [Int64: ChatState] = [:]
    private var lastUpdateId: Int64 = 0

    init(token: String, settings: SettingsStore) {
        self.token = token
        self.settings = settings
        self.baseURL = URL(string: "https://api.telegram.org/bot\(token)")!
    }

    func runForever() async {
        while true {
            do {
                let updates = try await getUpdates()
                for u in updates {
                    lastUpdateId = max(lastUpdateId, u.update_id)
                    await handle(update: u)
                }
            } catch {
                print("[TG] error:", error)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func sendLog(_ text: String) async {
        let chats = await settings.allLogChats()
        guard !chats.isEmpty else { return }
        for chatId in chats {
            _ = try? await sendMessage(chatId: chatId, text: text, markup: nil)
        }
    }

    private func getUpdates() async throws -> [TGUpdate] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("getUpdates"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "timeout", value: "30"),
            URLQueryItem(name: "offset", value: String(lastUpdateId + 1))
        ]

        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let resp = try JSONDecoder().decode(TGGetUpdatesResponse.self, from: data)

        if resp.ok { return resp.result ?? [] }
        print("[TG] getUpdates error:", resp.description ?? "unknown")
        return []
    }

    @discardableResult
    private func sendMessage(
        chatId: Int64,
        text: String,
        markup: TGInlineKeyboardMarkup?
    ) async throws -> TGMessage {

        var req = URLRequest(url: baseURL.appendingPathComponent("sendMessage"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = TGSendMessageRequest(chat_id: chatId, text: text, reply_markup: markup)
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TGSendMessageResponse.self, from: data)

        if resp.ok, let msg = resp.result { return msg }

        print("[TG] sendMessage error:", resp.description ?? "unknown")
        throw TGSimpleError.sendFailed
    }

    private func sendEphemeralMessage(chatId: Int64, text: String) async {
        if let msg = try? await sendMessage(chatId: chatId, text: text, markup: nil) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await deleteMessage(chatId: chatId, messageId: msg.message_id)
        }
    }

    private func deleteMessage(chatId: Int64, messageId: Int64) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("deleteMessage"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["chat_id": chatId, "message_id": messageId] as [String : Any]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try? await URLSession.shared.data(for: req)
    }

    private func answerCallbackQuery(id: String) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("answerCallbackQuery"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["callback_query_id": id]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try? await URLSession.shared.data(for: req)
    }

    private func helpText(authorized: Bool) -> String {
        if authorized {
            return """
            Доступные команды:
            /settings — настройки сообщений
            /develop_settings — developer-настройки
            /ping
            """
        } else {
            return "/start <пароль> — авторизация"
        }
    }

    private func handle(update: TGUpdate) async {
        if let cb = update.callback_query {
            await handle(callback: cb)
        } else if let msg = update.message {
            await handle(message: msg)
        }
    }

    private func handle(message: TGMessage) async {
        let chatId = message.chat.id
        let text = message.text ?? ""

        if text == "/ping" {
            _ = try? await sendMessage(chatId: chatId, text: "pong", markup: nil)
            return
        }

        if text.hasPrefix("/start") {
            await handleStart(text: text, chatId: chatId)
            return
        }

        let authorized = authorizedChats.contains(chatId)
        guard authorized else {
            _ = try? await sendMessage(chatId: chatId, text: helpText(authorized: false), markup: nil)
            return
        }

        if text == "/settings" {
            await showSettings(for: chatId)
            return
        }

        if text == "/develop_settings" {
            await showDevelopSettings(for: chatId)
            return
        }

        let state = states[chatId] ?? .idle

        switch state {

        case .waitingNewMessage1:
            states[chatId] = .confirmNewMessage1(text)
            await showConfirmNewMessage1(for: chatId, draft: text)
            return

        case .waitingNewMessage2:
            states[chatId] = .confirmNewMessage2(text)
            await showConfirmNewMessage2(for: chatId, draft: text)
            return

        case .waitingNewPassword:
            states[chatId] = .confirmNewPassword(text)
            await showConfirmNewPassword(for: chatId, draft: text)
            return

        default:
            break
        }

        _ = try? await sendMessage(chatId: chatId, text: helpText(authorized: true), markup: nil)
    }

    private func handle(callback: TGCallbackQuery) async {
        guard let chatId = callback.message?.chat.id else {
            await answerCallbackQuery(id: callback.id)
            return
        }

        let data = callback.data ?? ""
        let isAuth = authorizedChats.contains(chatId)

        guard isAuth else {
            await answerCallbackQuery(id: callback.id)
            return
        }

        switch data {

        case "edit_msg1":
            states[chatId] = .waitingNewMessage1
            _ = try? await sendMessage(chatId: chatId,
                                       text: "Отправь *стартовое сообщение* одним сообщением.",
                                       markup: nil)

        case "toggle_send1":
            let enabled = await settings.toggleSendMessages()
            await sendEphemeralMessage(chatId: chatId,
                       text: "Стартовое сообщение: \(enabled ? "вкл" : "выкл")")
            await showSettings(for: chatId)

        case "confirm_new_msg1":
            if case let .confirmNewMessage1(draft) = states[chatId] {
                await settings.setMessageTemplate(draft)
                states[chatId] = .idle
                await sendEphemeralMessage(chatId: chatId, text: "Стартовое сообщение обновлено.")
                await showSettings(for: chatId)
            }

        case "cancel_new_msg1":
            states[chatId] = .idle
            await sendEphemeralMessage(chatId: chatId, text: "Отменено.")

        case "edit_msg2":
            states[chatId] = .waitingNewMessage2
            _ = try? await sendMessage(chatId: chatId,
                                       text: "Отправь *второе сообщение* одним сообщением.",
                                       markup: nil)
        case "toggle_send2":
            let enabled = await settings.toggleSendSecondMessage()
            await sendEphemeralMessage(chatId: chatId,
                                      text: "Второе сообщение: \(enabled ? "вкл" : "выкл")")
            await showSettings(for: chatId)

        case "confirm_new_msg2":
            if case let .confirmNewMessage2(draft) = states[chatId] {
                await settings.setSecondMessageTemplate(draft)
                states[chatId] = .idle
                await sendEphemeralMessage(chatId: chatId, text: "Второе сообщение обновлено.")
                await showSettings(for: chatId)
            }

        case "cancel_new_msg2":
            states[chatId] = .idle
            await sendEphemeralMessage(chatId: chatId, text: "Отменено.")

        case "change_pass":
            states[chatId] = .waitingNewPassword
            _ = try? await sendMessage(chatId: chatId,
                                       text: "Отправь новый пароль одним сообщением.",
                                       markup: nil)

        case "confirm_new_pass":
            if case let .confirmNewPassword(pass) = states[chatId] {
                await settings.setPassword(pass)
                states[chatId] = .idle
                await sendEphemeralMessage(chatId: chatId, text: "Пароль изменён.")
                await showDevelopSettings(for: chatId)
            }

        case "cancel_new_pass":
            states[chatId] = .idle
            await sendEphemeralMessage(chatId: chatId, text: "Отменено.")

        case "toggle_logs":
            let enabled = await settings.toggleLogs(forChat: chatId)
            await sendEphemeralMessage(chatId: chatId,
                                       text: enabled ? "Логи включены" : "Логи выключены")
            await showDevelopSettings(for: chatId)

        default:
            break
        }

        await answerCallbackQuery(id: callback.id)
    }

    private func handleStart(text: String, chatId: Int64) async {
        let comps = text.split(separator: " ")
        guard comps.count == 2 else {
            _ = try? await sendMessage(chatId: chatId, text: "Используй: /start <пароль>", markup: nil)
            return
        }

        let pass = String(comps[1])
        let s = await settings.snapshot()

        if pass == s.password {
            authorizedChats.insert(chatId)
            _ = try? await sendMessage(chatId: chatId,
                                       text: "Авторизация успешна. Используй /settings.",
                                       markup: nil)
        } else {
            _ = try? await sendMessage(chatId: chatId, text: "Неверный пароль.", markup: nil)
        }
    }

    private func showSettings(for chatId: Int64) async {
        let s = await settings.snapshot()

        func preview(_ t: String) -> String {
            if t.count <= 60 { return t }
            return String(t.prefix(60)) + "..."
        }

        let text = """
        Настройки сообщений:

        • Стартовое сообщение — \(s.sendMessages ? "включено ✅" : "выключено ❌")
        \(s.messageTemplate)

        • Второе сообщение — \(s.sendSecondMessage ? "включено ✅" : "выключено ❌")
        \(s.secondMessageTemplate)
        """

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "Изменить стартовое", callback_data: "edit_msg1"),
                TGInlineKeyboardButton(text: s.sendMessages ? "Старт: выключить" : "Старт: включить",
                                       callback_data: "toggle_send1")
            ],
            [
                TGInlineKeyboardButton(text: "Изменить второе", callback_data: "edit_msg2"),
                TGInlineKeyboardButton(text: s.sendSecondMessage ? "Второе: выключить" : "Второе: включить",
                                       callback_data: "toggle_send2")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showDevelopSettings(for chatId: Int64) async {
        let s = await settings.snapshot()
        let logChats = s.logChatIds ?? []

        var lines = [String]()
        lines.append("Developer settings:")
        lines.append("")
        lines.append("• Пароль: ********")

        if logChats.isEmpty {
            lines.append("• Логи: выключены")
        } else if logChats.contains(chatId) {
            lines.append("• Логи: включены (этот чат)")
        } else {
            lines.append("• Логи: включены (другие чаты)")
        }

        let text = lines.joined(separator: "\n")

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "Изменить пароль", callback_data: "change_pass")
            ],
            [
                TGInlineKeyboardButton(text: logChats.contains(chatId) ? "Выключить логи" : "Включить логи",
                                       callback_data: "toggle_logs")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showConfirmNewMessage1(for chatId: Int64, draft: String) async {
        let text = """
        Новый текст *стартового* сообщения:

        \(draft)

        Подтвердить?
        """
        let markup = TGInlineKeyboardMarkup(inline_keyboard: [[
            TGInlineKeyboardButton(text: "✅", callback_data: "confirm_new_msg1"),
            TGInlineKeyboardButton(text: "❌", callback_data: "cancel_new_msg1")
        ]])
        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showConfirmNewMessage2(for chatId: Int64, draft: String) async {
        let text = """
        Новый текст *второго* сообщения:

        \(draft)

        Подтвердить?
        """
        let markup = TGInlineKeyboardMarkup(inline_keyboard: [[
            TGInlineKeyboardButton(text: "✅", callback_data: "confirm_new_msg2"),
            TGInlineKeyboardButton(text: "❌", callback_data: "cancel_new_msg2")
        ]])
        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showConfirmNewPassword(for chatId: Int64, draft: String) async {
        let text = """
        Новый пароль:

        \(draft)

        Подтвердить?
        """
        let markup = TGInlineKeyboardMarkup(inline_keyboard: [[
            TGInlineKeyboardButton(text: "✅", callback_data: "confirm_new_pass"),
            TGInlineKeyboardButton(text: "❌", callback_data: "cancel_new_pass")
        ]])
        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }
}

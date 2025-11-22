//
//  TelegramBot.swift
//  WheelOrder
//
//  Created by Вячеслав on 22.11.2025.
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
        case waitingNewMessage
        case confirmNewMessage(String)
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
        let logChats = await settings.allLogChats()
        guard !logChats.isEmpty else { return }

        for chatId in logChats {
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
        if resp.ok {
            return resp.result ?? []
        } else {
            print("[TG] getUpdates error:", resp.description ?? "unknown")
            return []
        }
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

        let payload = TGSendMessageRequest(
            chat_id: chatId,
            text: text,
            reply_markup: markup
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TGSendMessageResponse.self, from: data)

        if resp.ok, let msg = resp.result {
            return msg
        } else {
            print("[TG] sendMessage error:", resp.description ?? "unknown")
            throw TGSimpleError.sendFailed
        }
    }

    private func editMessageText(
        chatId: Int64,
        messageId: Int64,
        text: String,
        markup: TGInlineKeyboardMarkup?
    ) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("editMessageText"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = TGEditMessageTextRequest(
            chat_id: chatId,
            message_id: messageId,
            text: text,
            reply_markup: markup
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let resp = try? JSONDecoder().decode(TGSendMessageResponse.self, from: data),
           !resp.ok {
            print("[TG] editMessageText error:", resp.description ?? "unknown")
        }
    }

    private func deleteMessage(chatId: Int64, messageId: Int64) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("deleteMessage"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        _ = try? await URLSession.shared.data(for: req)
    }

    private func sendEphemeralMessage(chatId: Int64, text: String) async {
        if let msg = try? await sendMessage(chatId: chatId, text: text, markup: nil) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await deleteMessage(chatId: chatId, messageId: msg.message_id)
        }
    }

    private func answerCallbackQuery(id: String) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("answerCallbackQuery"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["callback_query_id": id]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        _ = try? await URLSession.shared.data(for: req)
    }

    private func helpText(authorized: Bool) -> String {
        if authorized {
            return """
            Доступные команды:
            /settings — пользовательские настройки
            /develop_settings — developer-настройки
            /ping
            """
        } else {
            return """
            Доступные команды:
            /start <пароль> — авторизация
            """
        }
    }

    private func handle(update: TGUpdate) async {
        if let cb = update.callback_query {
            await handle(callback: cb)
            return
        }
        if let msg = update.message {
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

        let isAuthorized = authorizedChats.contains(chatId)

        guard isAuthorized else {
            _ = try? await sendMessage(
                chatId: chatId,
                text: helpText(authorized: false),
                markup: nil
            )
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
        case .waitingNewMessage:
            states[chatId] = .confirmNewMessage(text)
            await showConfirmNewMessage(for: chatId, draft: text)
            return

        case .waitingNewPassword:
            states[chatId] = .confirmNewPassword(text)
            await showConfirmNewPassword(for: chatId, draft: text)
            return

        default:
            break
        }

        _ = try? await sendMessage(
            chatId: chatId,
            text: helpText(authorized: true),
            markup: nil
        )
    }

    private func handle(callback: TGCallbackQuery) async {
        guard let chatId = callback.message?.chat.id else {
            await answerCallbackQuery(id: callback.id)
            return
        }
        let data = callback.data ?? ""

        guard authorizedChats.contains(chatId) else {
            await answerCallbackQuery(id: callback.id)
            return
        }

        switch data {

        case "edit_msg":
            states[chatId] = .waitingNewMessage
            _ = try? await sendMessage(
                chatId: chatId,
                text: "Отправь новый текст стандартного сообщения одним сообщением.",
                markup: nil
            )

        case "toggle_logs":
            let enabledForThisChat = await settings.toggleLogs(forChat: chatId)
            let text = enabledForThisChat
                ? "Логи включены в этом чате."
                : "Логи выключены в этом чате."
            await sendEphemeralMessage(chatId: chatId, text: text)
            await showDevelopSettings(for: chatId)

        case "toggle_sending":
            let enabled = await settings.toggleSendMessages()
            await sendEphemeralMessage(
                chatId: chatId,
                text: "Отправка сообщений: \(enabled ? "включена" : "выключена")"
            )
            await showSettings(for: chatId)

        case "change_pass":
            states[chatId] = .waitingNewPassword
            _ = try? await sendMessage(
                chatId: chatId,
                text: "Отправь новый пароль одним сообщением.",
                markup: nil
            )

        case "confirm_new_msg":
            if case let .confirmNewMessage(draft) = states[chatId] {
                await settings.setMessageTemplate(draft)
                states[chatId] = .idle
                await sendEphemeralMessage(chatId: chatId, text: "Стандартное сообщение обновлено.")
                await showSettings(for: chatId)
            }

        case "cancel_new_msg":
            states[chatId] = .idle
            await sendEphemeralMessage(chatId: chatId, text: "Изменение сообщения отменено.")

        case "confirm_new_pass":
            if case let .confirmNewPassword(draft) = states[chatId] {
                await settings.setPassword(draft)
                states[chatId] = .idle
                await sendEphemeralMessage(chatId: chatId, text: "Пароль обновлён.")
                await showDevelopSettings(for: chatId)
            }

        case "cancel_new_pass":
            states[chatId] = .idle
            await sendEphemeralMessage(chatId: chatId, text: "Изменение пароля отменено.")

        default:
            break
        }

        await answerCallbackQuery(id: callback.id)
    }

    private func handleStart(text: String, chatId: Int64) async {
        let components = text.split(separator: " ")
        guard components.count == 2 else {
            _ = try? await sendMessage(
                chatId: chatId,
                text: "Используй: /start <пароль>",
                markup: nil
            )
            return
        }

        let pass = String(components[1])
        let s = await settings.snapshot()

        if pass == s.password {
            authorizedChats.insert(chatId)
            _ = try? await sendMessage(
                chatId: chatId,
                text: "Авторизация успешна. Используй /settings и /develop_settings для управления.",
                markup: nil
            )
        } else {
            _ = try? await sendMessage(
                chatId: chatId,
                text: "Неверный пароль.",
                markup: nil
            )
        }
    }

    private func showSettings(for chatId: Int64) async {
        let s = await settings.snapshot()

        let text = """
        Текущие настройки:

        • Стандартное сообщение:
        \(s.messageTemplate)

        • Отправка сообщений: \(s.sendMessages ? "включена" : "выключена")
        """

        let sendingButtonTitle = s.sendMessages ? "Выключить отправку" : "Включить отправку"

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "Изменить стандартное сообщение", callback_data: "edit_msg")
            ],
            [
                TGInlineKeyboardButton(text: sendingButtonTitle, callback_data: "toggle_sending")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showDevelopSettings(for chatId: Int64) async {
        let s = await settings.snapshot()
        let logChats = s.logChatIds ?? []

        var lines: [String] = []
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

        let enabledForThisChat = logChats.contains(chatId)
        let logsTitle = enabledForThisChat
            ? "Выключить логи в этом чате"
            : "Включить логи в этом чате"

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "Изменить пароль", callback_data: "change_pass")
            ],
            [
                TGInlineKeyboardButton(text: logsTitle, callback_data: "toggle_logs")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showConfirmNewMessage(for chatId: Int64, draft: String) async {
        let text = """
        Новый текст стандартного сообщения:

        \(draft)

        Подтвердить изменения?
        """

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "✅ Подтвердить", callback_data: "confirm_new_msg"),
                TGInlineKeyboardButton(text: "❌ Отмена", callback_data: "cancel_new_msg")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }

    private func showConfirmNewPassword(for chatId: Int64, draft: String) async {
        let text = """
        Новый пароль: \(draft)

        Подтвердить изменения?
        """

        let markup = TGInlineKeyboardMarkup(inline_keyboard: [
            [
                TGInlineKeyboardButton(text: "✅ Подтвердить", callback_data: "confirm_new_pass"),
                TGInlineKeyboardButton(text: "❌ Отмена", callback_data: "cancel_new_pass")
            ]
        ])

        _ = try? await sendMessage(chatId: chatId, text: text, markup: markup)
    }
}

//
//  TGModels.swift
//  WheelOrder
//
//  Created by Вячеслав on 22.11.2025.
//

import Foundation

enum TGSimpleError: Error {
    case sendFailed
}

struct TGGetUpdatesResponse: Decodable {
    let ok: Bool
    let result: [TGUpdate]?
    let description: String?
}

struct TGUpdate: Decodable {
    let update_id: Int64
    let message: TGMessage?
    let callback_query: TGCallbackQuery?
}

struct TGCallbackQuery: Decodable {
    let id: String
    let from: TGUser
    let message: TGMessage?
    let data: String?
}

struct TGUser: Decodable {
    let id: Int64
    let is_bot: Bool?
    let first_name: String?
    let username: String?
}

struct TGMessage: Decodable {
    let message_id: Int64
    let chat: TGChat
    let text: String?
}

struct TGChat: Decodable {
    let id: Int64
}

struct TGInlineKeyboardMarkup: Codable {
    let inline_keyboard: [[TGInlineKeyboardButton]]
}

struct TGInlineKeyboardButton: Codable {
    let text: String
    let callback_data: String
}

struct TGSendMessageRequest: Encodable {
    let chat_id: Int64
    let text: String
    let reply_markup: TGInlineKeyboardMarkup?
}

struct TGSendMessageResponse: Decodable {
    let ok: Bool
    let result: TGMessage?
    let description: String?
}

struct TGEditMessageTextRequest: Encodable {
    let chat_id: Int64
    let message_id: Int64
    let text: String
    let reply_markup: TGInlineKeyboardMarkup?
}

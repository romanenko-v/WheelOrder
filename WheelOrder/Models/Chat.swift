//
//  Chat.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

struct ChatListRequest: Encodable { let limit: Int }
struct ChatListResponse: Decodable { let chats: [ChatListItem]? }
struct ChatListItem: Decodable { let chat: ChatMeta }
struct ChatMeta: Decodable {
    let chat_id: String
    let chat_status: String?
    let chat_type: String?
}

struct ChatHistoryRequest: Encodable { let chat_id: String }
struct ChatHistoryResponse: Decodable { let messages: [ChatMessage]? }
struct ChatMessage: Decodable {
    let message_id: FlexString
    let created_at: String?
}

struct ChatStartRequest: Encodable { let posting_number: String }
struct ChatStartResponse: Decodable {
    let result: Result?
    let chat_id: String?
    struct Result: Decodable { let chat_id: String? }
    var resolvedChatId: String? { result?.chat_id ?? chat_id }
}

struct ChatSendRequest: Encodable {
    let chat_id: String
    let text: String
}

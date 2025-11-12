//
//  OzonSellerAPI.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

final class OzonSellerAPI {
    private let http: OzonHTTP
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(clientId: String, apiKey: String) {
        self.http = OzonHTTP(clientId: clientId, apiKey: apiKey)
    }

    func listChats(limit: Int = 100) async throws -> [ChatListItem] {
        let res: ChatListResponse = try await http.post("/v3/chat/list",
                                                        body: ChatListRequest(limit: limit),
                                                        as: ChatListResponse.self)
        return res.chats ?? []
    }

    func chatHistory(chatId: String) async throws -> [ChatMessage] {
        let res: ChatHistoryResponse = try await http.post("/v3/chat/history",
                                                           body: ChatHistoryRequest(chat_id: chatId),
                                                           as: ChatHistoryResponse.self)
        return res.messages ?? []
    }

    func createChat(forPosting postingNumber: String) async throws -> String {
        let res: ChatStartResponse = try await http.post("/v1/chat/start",
                                                         body: ChatStartRequest(posting_number: postingNumber),
                                                         as: ChatStartResponse.self)
        guard let cid = res.resolvedChatId, !cid.isEmpty else {
            throw NSError(domain: "OZON", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "chat_id not found in /v1/chat/start"])
        }
        return cid
    }

    func sendMessage(chatId: String, text: String) async throws {
        try await http.postVoid("/v1/chat/send/message", body: ChatSendRequest(chat_id: chatId, text: text))
    }

    func listAwaitingPackagingPage(from: Date, to: Date, limit: Int = 100, offset: Int = 0) async throws -> [FBSPosting] {
        let req = FBSListRequest(
            filter: .init(since: iso.string(from: from),
                          to: iso.string(from: to),
                          status: "awaiting_packaging"),
            limit: min(limit, 100),
            offset: offset
        )
        let res: FBSListResponse = try await http.post("/v3/posting/fbs/list", body: req, as: FBSListResponse.self)
        return res.result?.postings ?? []
    }

    func listAwaitingPackagingAll(from: Date, to: Date) async throws -> [FBSPosting] {
        var acc: [FBSPosting] = []
        var offset = 0
        while true {
            let page = try await listAwaitingPackagingPage(from: from, to: to, limit: 100, offset: offset)
            if page.isEmpty { break }
            acc.append(contentsOf: page)
            offset += page.count
        }
        return acc
    }
}

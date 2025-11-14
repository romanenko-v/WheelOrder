//
//  OrderChatWorker.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

final class OrderChatWorker {
    private let api: OzonSellerAPI
    private let cache: PostingCache
    private let windowHours: Int
    private let loopIntervalSec: UInt64
    private let sendMessages: Bool
    private let throttleNs: UInt64 = 200_000_000

    init(api: OzonSellerAPI,
         cache: PostingCache,
         windowHours: Int = 5,
         loopIntervalSec: UInt64 = 60,
         sendMessages: Bool = true) {
        self.api = api
        self.cache = cache
        self.windowHours = windowHours
        self.loopIntervalSec = loopIntervalSec
        self.sendMessages = sendMessages
    }

    func runForever() async {
        while true {
            await runOnce()
            try? await Task.sleep(nanoseconds: loopIntervalSec * 1_000_000_000)
        }
    }

    func runOnce() async {
        pruneCache()

        let (from, to) = timeWindow(hours: windowHours)
        do {
            let postings = try await fetchNewPostings(from: from, to: to)
            guard !postings.isEmpty else {
                log("No new postings found")
                return
            }
            log("Found \(postings.count) postings in awaiting_packaging")

            for posting in postings {
                await processPosting(posting)
                try? await Task.sleep(nanoseconds: throttleNs)
            }
        } catch {
            log("Cycle error: \(error)")
        }
    }
}

private extension OrderChatWorker {
    func pruneCache() {
        cache.pruneOlderThan(hours: 24)
    }

    func timeWindow(hours: Int) -> (from: Date, to: Date) {
        let to = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -hours, to: to)!
        return (from, to)
    }

    func fetchNewPostings(from: Date, to: Date) async throws -> [FBSPosting] {
        try await api.listAwaitingPackagingAll(from: from, to: to)
    }

    func processPosting(_ posting: FBSPosting) async {
        let pn = posting.posting_number
        if cache.contains(pn) { return }

        do {
            let chatId = try await createOrGetChatId(for: pn)
            await handleNoMessages(postingNumber: pn, chatId: chatId)
//            let messages = try await fetchChatMessages(chatId: chatId)
//
//            if messages.isEmpty {
//                await handleNoMessages(postingNumber: pn, chatId: chatId)
//            } else {
//                await handleExistingMessages(postingNumber: pn, messageCount: messages.count)
//            }
        } catch {
            log("  \(pn): failed to process posting (\(error))")
        }
    }

    func createOrGetChatId(for postingNumber: String) async throws -> String {
        do {
            let chatId = try await api.createChat(forPosting: postingNumber)
            return chatId
        } catch {
            throw error
        }
    }

    func fetchChatMessages(chatId: String) async throws -> [ChatMessage] {
        try await api.chatHistory(chatId: chatId)
    }

    func handleNoMessages(postingNumber: String, chatId: String) async {
        if sendMessages {
            do {
                try await api.sendMessage(chatId: chatId, text: Config.makePostingMessage(postingNumber: postingNumber))
                log("  \(postingNumber): sent initial message to chat \(chatId)")
                cache.insert(postingNumber)
            } catch {
                log("  \(postingNumber): failed to send message (\(error))")
            }
        } else {
            log("  \(postingNumber): dry run — no messages in chat")
            cache.insert(postingNumber)
        }
    }

    func handleExistingMessages(postingNumber: String, messageCount: Int) async {
        log("  \(postingNumber): chat already contains \(messageCount) messages")
        cache.insert(postingNumber)
    }

    func log(_ message: String) {
        print("[\(Date())] \(message)")
    }
}

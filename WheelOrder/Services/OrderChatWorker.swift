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
    private let secondCache: SecondMessageCache

    private let windowHours: Int
    private let loopIntervalSec: UInt64
    private let settings: SettingsStore
    private let throttleNs: UInt64 = 200_000_000

    private let secondMessageDelayHours: Int = 12

    init(api: OzonSellerAPI,
         cache: PostingCache,
         windowHours: Int = 5,
         loopIntervalSec: UInt64 = 60,
         settings: SettingsStore) {
        self.api = api
        self.cache = cache
        self.secondCache = SecondMessageCache.shared
        self.windowHours = windowHours
        self.loopIntervalSec = loopIntervalSec
        self.settings = settings
    }

    func runForever() async {
        while true {
            await runOnce()
            try? await Task.sleep(nanoseconds: loopIntervalSec * 1_000_000_000)
        }
    }

    func runOnce() async {
        pruneCache()
        await processSecondMessagesQueue()
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
        secondCache.pruneOlderThan(hours: 24)
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
        let cfg = await settings.snapshot()

        guard cfg.sendMessages else {
            log("  \(postingNumber): dry run — sendMessages=false, no messages in chat")
            cache.insert(postingNumber)
            secondCache.remove(postingNumber)
            return
        }

        do {
            let text = Config.makePostingMessage(
                postingNumber: postingNumber,
                messageText: cfg.messageTemplate
            )
            try await api.sendMessage(chatId: chatId, text: text)
            log("  \(postingNumber): sent initial message to chat \(chatId)")

            cache.insert(postingNumber)
            secondCache.insert(postingNumber)

        } catch {
            log("  \(postingNumber): failed to send initial message (\(error))")
        }
    }

    func handleExistingMessages(postingNumber: String, messageCount: Int) async {
        log("  \(postingNumber): chat already contains \(messageCount) messages")
        cache.insert(postingNumber)
    }

    func processSecondMessagesQueue() async {
        let cfg = await settings.snapshot()
        let now = Date()

        let threshold = now.addingTimeInterval(-TimeInterval(secondMessageDelayHours * 3600))

        let duePostings = secondCache.postings(olderThanOrEqualTo: threshold)
        guard !duePostings.isEmpty else { return }

        log("Processing \(duePostings.count) postings for second message")
        for pn in duePostings {
            if !cfg.sendSecondMessage {
                log("  \(pn): second message skipped (disabled in config)")
                secondCache.remove(pn)
                continue
            }

            do {
                let chatId = try await createOrGetChatId(for: pn)
                let text = cfg.secondMessageTemplate

                try await api.sendMessage(chatId: chatId, text: text)
                log("  \(pn): sent second message to chat \(chatId)")

                secondCache.remove(pn)

            } catch {
                log("  \(pn): failed to send second message (\(error))")
                secondCache.remove(pn)
            }
        }
    }

    func log(_ message: String) {
        let line = "[\(Date())] \(message)"
        print(line)
    }
}

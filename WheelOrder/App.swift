import Foundation

@main
struct App {
    static func main() async {
        let api = OzonSellerAPI(clientId: Config.OZON_CLIENT_ID, apiKey: Config.OZON_API_KEY)
        let cache = PostingCache()
//        cache.clear()

        let worker = OrderChatWorker(api: api,
                                     cache: cache,
                                     windowHours: 3,
                                     loopIntervalSec: 60,
                                     sendMessages: true)

        await worker.runForever()
    }
}

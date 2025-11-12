import Foundation

#if os(Linux)
import Glibc
@inline(__always)
private func disableStdIOBuffering() {
    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
}
#else
@inline(__always)
private func disableStdIOBuffering() {}
#endif

@main
struct App {
    static func main() async {
        disableStdIOBuffering()

        let api = OzonSellerAPI(clientId: Config.OZON_CLIENT_ID, apiKey: Config.OZON_API_KEY)
        let cache = PostingCache()
        // cache.clear()

        let worker = OrderChatWorker(api: api,
                                     cache: cache,
                                     windowHours: 3,
                                     loopIntervalSec: 60,
                                     sendMessages: true)

        await worker.runForever()
    }
}

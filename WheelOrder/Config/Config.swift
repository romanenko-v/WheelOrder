//
//  Config.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

enum Config {
    static var OZON_CLIENT_ID: String = ProcessInfo.processInfo.environment["OZON_CLIENT_ID"] ?? ""
    static var OZON_API_KEY:   String = ProcessInfo.processInfo.environment["OZON_API_KEY"] ?? ""
    static var TELEGRAM_BOT_TOKEN: String = ProcessInfo.processInfo.environment["TELEGRAM_BOT_TOKEN"] ?? ""

    static let MESSAGE_TEXT = """
    Добрый день! Мы хотим убедиться в правильности подбора параметров по вашему заказу. Для этого сообщите, пожалуйста, марку и модель автомобиля (по возможности укажите год выпуска и объем двигателя) для которого приобретаются диски, чтобы мы могли проверить их совместимость.
    """

    static func makePostingMessage(postingNumber: String,  messageText: String = MESSAGE_TEXT) -> String {
        let url = "https://seller.ozon.ru/app/postings/fbs?postingDetails=\(postingNumber)"
        
        return """
        \(messageText)

        \(url)
        """
    }
}

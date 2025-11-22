//
//  GlobalLogger.swift
//  WheelOrder
//
//  Created by Вячеслав on 22.11.2025.
//

import Foundation

actor GlobalLogger {
    static let shared = GlobalLogger()

    private var bot: TelegramBot?

    func configure(bot: TelegramBot) {
        self.bot = bot
    }

    func logRemote(_ text: String) async {
        await bot?.sendLog(text)
    }
}

public func print(
    _ items: Any...,
    separator: String = " ",
    terminator: String = "\n"
) {
    let text = items.map { "\($0)" }.joined(separator: separator)

    let full = text + terminator
    if let data = full.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }

    Task {
        await GlobalLogger.shared.logRemote(text)
    }
}


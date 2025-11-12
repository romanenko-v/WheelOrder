//
//  FlexString.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

struct FlexString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int64.self)  { value = String(i); return }
        if let d = try? c.decode(Double.self) { value = String(format: "%.0f", d); return }
        value = ""
    }
}

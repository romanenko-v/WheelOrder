//
//  FBS.swift
//  WheelOrder
//
//  Created by Вячеслав on 12.11.2025.
//

import Foundation

struct FBSListRequest: Encodable {
    struct Filter: Encodable {
        let since: String
        let to: String
        let status: String
    }
    let dir: String = "ASC"
    let filter: Filter
    let limit: Int
    let offset: Int
    let with: With = With()
    struct With: Encodable {
        let analytics_data: Bool = false
        let financial_data: Bool = false
        let barcodes: Bool = false
        let translit: Bool = false
    }
}

struct FBSListResponse: Decodable {
    struct Result: Decodable { let postings: [FBSPosting]? }
    let result: Result?
}

struct FBSPosting: Decodable {
    let posting_number: String
    let status: String?
    let in_process_at: String?
    let shipment_date: String?
}

struct FBSGetRequest: Encodable {
    let posting_number: String
}

struct FBSGetResponse: Decodable {
    let result: FBSPostingFull?
}

struct FBSPostingFull: Decodable {
    let posting_number: String?
    let products: [FBSPostingProduct]?
}

struct FBSPostingProduct: Decodable {
    let name: String?
    let quantity: Int?
}

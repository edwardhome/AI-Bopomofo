// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 只在背景呼叫。取消／草稿失效時只移除本次寫入的內容，不刪除較新的提議。
public enum CardProposalPersistence {
    public static func write(_ data: Data, to path: URL) throws {
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    @discardableResult public static func discard(_ data: Data, at path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        let file = try FileHandle(forReadingFrom: path); defer { try? file.close() }
        guard try file.read(upToCount: data.count + 1) == data else { return false }
        try FileManager.default.removeItem(at: path); return true
    }
}

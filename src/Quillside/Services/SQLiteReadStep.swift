import Foundation
import SQLite3

enum SQLiteReadStep {
    static func next(_ statement: OpaquePointer?) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let code:
            throw AIError.message("数据库读取未完成（SQLite \(code)），请稍后重试。")
        }
    }
}

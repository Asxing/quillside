import Foundation

struct NotesFolderIdentity {
    struct Folder {
        let pk: Int64
        let identifier: String
        let name: String
        let parent: Int64?
        let owner: Int64?
    }
    struct Account { let pk: Int64; let identifier: String; let name: String }
    struct Scope { let id: String; let name: String; let detail: String }

    static func resolve(noteIdentifier: String, folderPK: Int64?, noteAccountPK: Int64?, store: String,
                        folders: [Int64: Folder], accounts: [Int64: Account]) -> Scope {
        guard let folderPK, let leaf = folders[folderPK] else {
            return .init(id: "unresolved-source:" + noteIdentifier, name: "未归档", detail: "来源身份待确认")
        }
        var path: [String] = [], owners = Set<Int64>(), visited = Set<Int64>(), current: Int64? = folderPK
        if let noteAccountPK, noteAccountPK > 0 { owners.insert(noteAccountPK) }
        while let pk = current, let folder = folders[pk] {
            guard visited.insert(pk).inserted, visited.count <= 64 else {
                return .init(id: "unresolved-source:" + noteIdentifier, name: leaf.name, detail: "文件夹层级待确认")
            }
            path.insert(folder.name.isEmpty ? "Notes" : folder.name, at: 0)
            if let owner = folder.owner, owner > 0 { owners.insert(owner) }
            current = folder.parent
        }
        guard owners.count <= 1 else {
            return .init(id: "unresolved-source:" + noteIdentifier, name: path.joined(separator: " / "), detail: "账户身份待确认")
        }
        let owner = owners.first
        let account = owner.flatMap { accounts[$0] }
        let accountIdentity = account.map { "\($0.identifier)|local:\($0.pk)" } ?? owner.map { "local:\($0)" } ?? "unresolved"
        // Local row identity also disambiguates special identifiers such as DefaultFolder-CloudKit.
        let folderIdentity = "\(leaf.identifier)|local:\(leaf.pk)"
        return .init(id: KnowledgeCollectionIdentity.notes(store: store, account: accountIdentity, folder: folderIdentity),
                     name: path.joined(separator: " / "), detail: account?.name.isEmpty == false ? account!.name : "未识别账户")
    }
}

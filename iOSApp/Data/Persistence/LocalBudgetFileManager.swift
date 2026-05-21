import Foundation

public final class LocalBudgetFileManager {
    public static let shared = LocalBudgetFileManager()
    
    private init() {}
    
    public var budgetsDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0]
        let budgetsDir = appSupport.appendingPathComponent("Budgets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: budgetsDir.path) {
            try? FileManager.default.createDirectory(at: budgetsDir, withIntermediateDirectories: true, attributes: nil)
        }
        return budgetsDir
    }
    
    public func budgetDirectory(for budgetId: String) -> URL {
        return budgetsDirectory.appendingPathComponent(budgetId, isDirectory: true)
    }
    
    public func sqliteFileURL(for budgetId: String) -> URL {
        return budgetDirectory(for: budgetId).appendingPathComponent("budget.sqlite")
    }
    
    public func metadataFileURL(for budgetId: String) -> URL {
        return budgetDirectory(for: budgetId).appendingPathComponent("budget-metadata.json")
    }
    
    public func createBudgetDirectory(for budgetId: String) throws {
        let dir = budgetDirectory(for: budgetId)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    public func listBudgets() -> [(id: String, displayName: String)] {
        let dir = budgetsDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        var list = [(id: String, displayName: String)]()
        for url in urls where url.hasDirectoryPath {
            let id = url.lastPathComponent
            let metaURL = metadataFileURL(for: id)
            var displayName = id
            if let data = try? Data(contentsOf: metaURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["displayName"] as? String {
                displayName = name
            }
            list.append((id: id, displayName: displayName))
        }
        return list
    }
    
    public func deleteBudget(budgetId: String) throws {
        let dir = budgetDirectory(for: budgetId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }
}
import Foundation

// This enum defines the two states our sheet can be in: adding a new transaction,
// or editing an existing one. It's Identifiable so SwiftUI's .sheet(item:...) modifier can use it.
enum SheetType: Identifiable {
    case add
    case edit(Transaction)
    case importCSV

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let transaction):
            // Use the transaction's ID to uniquely identify the edit sheet
            return transaction.id ?? UUID().uuidString
        case .importCSV:
            return "importCSV"
        }
    }
}
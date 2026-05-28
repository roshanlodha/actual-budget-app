import Foundation
import FoundationModels

@Generable
public struct AutoCategoryResponse {
    @Guide(description: "The name of the best matching category from the allowed list, or 'Other' if no categories fit.")
    public let categoryName: String
    
    public init(categoryName: String) {
        self.categoryName = categoryName
    }
}

public final class AutoClassifier {
    public static let shared = AutoClassifier()
    
    private init() {}
    
    /// Auto-detects the best category for a transaction based on payee name and notes.
    /// - Parameters:
    ///   - payeeName: The name of the payee.
    ///   - notes: Any associated notes/memo.
    ///   - categories: The user's list of categories.
    /// - Returns: The predicted category ID, or nil if categorized as 'Other' or detection fails.
    public func autoCategorize(payeeName: String, notes: String, categories: [Category]) async -> String? {
        let cleanPayee = payeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanPayee.isEmpty || !cleanNotes.isEmpty else {
            return nil
        }
        
        let categoryNames = categories.map { $0.name }
        
        // Setup prompt (no specific brand names mentioned)
        let prompt = """
        You are a financial assistant classifying bank transactions.
        
        Transaction Payee: "\(cleanPayee)"
        Transaction Notes: "\(cleanNotes)"
        
        Allowed Categories:
        \(categoryNames.joined(separator: ", "))
        
        Analyze the payee and notes to identify the category. For example:
        - Flight, airline, hotel, car rental, or travel agency matches 'Travel'.
        - Supermarket, food store, or organic market matches 'Groceries'.
        - Cafe, coffee shop, restaurant, diner, fast food, or pub matches 'Eating Out'.
        - Rent, housing, apartment lease, or mortgage matches 'Rent'.
        - Electricity, gas, water, internet, phone, or home/auto insurance matches 'Utilities, Internet, Insurance'.
        - Gas station, fuel, toll, parking, bus, train, or metro matches 'Transportation and Gas'.
        
        Select the best category from the Allowed Categories. If no categories fit, return 'Other'.
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: AutoCategoryResponse.self)
            let predictedName = response.content.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Match case-insensitively
            if let matchedCategory = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(predictedName) == .orderedSame }) {
                return matchedCategory.id
            }
        } catch {
            AppLogger.shared.log("Auto-categorization LLM failed: \(error.localizedDescription)", level: .error)
        }
        
        return nil
    }
}

import Foundation
import FoundationModels

public final class AutoClassifier {
    public static let shared = AutoClassifier()
    
    private init() {}
    
    /// Auto-detects the best category for a transaction based on payee name and notes.
    /// - Parameters:
    ///   - payeeName: The name of the payee.
    ///   - notes: Any associated notes/memo.
    ///   - categories: The user's list of categories.
    /// - Returns: The predicted category ID, or nil if detection fails.
    public func autoCategorize(payeeName: String, notes: String, categories: [Category]) async -> String? {
        let cleanPayee = payeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanPayee.isEmpty || !cleanNotes.isEmpty else {
            return nil
        }
        
        // Filter out "Other" from the category list to prevent bias, unless it's the only category
        let filteredCategories = categories.filter { $0.name.localizedCaseInsensitiveCompare("Other") != .orderedSame }
        let targetCategories = filteredCategories.isEmpty ? categories : filteredCategories
        
        // Dynamic list of user's categories
        let categoryList = targetCategories.map { $0.name }.joined(separator: ", ")
        
        let prompt = """
        You are a transaction categorization assistant.
        Your task is to categorize a financial transaction into one of these exact categories:
        \(categoryList)
        
        Here are examples of how to categorize payees:
        - If the payee is "Elevate Apartments" (has "Apartments" in it), the category is "Rent".
        - If the payee is "Pacific Gas and Electric", the category is "Utilities".
        - If the payee is "Whole Foods" or "Trader Joe's", the category is "Groceries".
        - If the payee is "Uber" or "Lyft", the category is "Travel" or "Transportation".
        - If the payee is "Amazon" or "Target", the category is "Shopping".
        - If the payee is "McDonalds" or "Uber Eats", the category is "Dining" or "Food".
        
        Based on the payee and notes, output ONLY the exact category name from the list above that matches best. Do NOT include any intro, explanation, period, quotation marks, or preamble. Just return the category name.
        
        Payee: "\(cleanPayee)"
        Notes: "\(cleanNotes)"
        Category:
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            
            // Clean up the predicted text
            var predictedName = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Strip any wrapping quotation marks the LLM might have output
            if (predictedName.hasPrefix("\"") && predictedName.hasSuffix("\"")) ||
               (predictedName.hasPrefix("'") && predictedName.hasSuffix("'")) {
                predictedName = String(predictedName.dropFirst().dropLast())
            }
            // Strip trailing period if any
            if predictedName.hasSuffix(".") {
                predictedName = String(predictedName.dropLast())
            }
            predictedName = predictedName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            AppLogger.shared.log("AutoClassifier: payee='\(cleanPayee)' predicted='\(predictedName)'", level: .info)
            
            // 1. Exact case-insensitive match
            if let match = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(predictedName) == .orderedSame }) {
                return match.id
            }
            
            // 2. Contains match (either way)
            if let match = categories.first(where: {
                $0.name.localizedCaseInsensitiveContains(predictedName) || predictedName.localizedCaseInsensitiveContains($0.name)
            }) {
                AppLogger.shared.log("AutoClassifier: contains matched '\(predictedName)' → '\(match.name)'", level: .info)
                return match.id
            }
            
            // 3. Fuzzy Levenshtein match
            if let bestMatch = findBestFuzzyMatch(for: predictedName, in: categories) {
                AppLogger.shared.log("AutoClassifier: fuzzy matched '\(predictedName)' → '\(bestMatch.name)'", level: .info)
                return bestMatch.id
            }
            
            AppLogger.shared.log("AutoClassifier: no match for '\(predictedName)' in categories", level: .warning)
        } catch {
            AppLogger.shared.log("Auto-categorization LLM failed: \(error.localizedDescription)", level: .error)
        }
        
        return nil
    }
    
    private func findBestFuzzyMatch(for target: String, in categories: [Category]) -> Category? {
        let cleanTarget = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else { return nil }
        
        var bestCategory: Category? = nil
        var bestSimilarity: Double = 0.0
        
        for category in categories {
            let cleanCat = category.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let dist = levenshteinDistance(s1: cleanTarget, s2: cleanCat)
            let maxLength = max(cleanTarget.count, cleanCat.count)
            guard maxLength > 0 else { continue }
            
            let similarity = 1.0 - (Double(dist) / Double(maxLength))
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestCategory = category
            }
        }
        
        // Only accept if similarity is at least 60%
        return bestSimilarity >= 0.6 ? bestCategory : nil
    }
    
    private func levenshteinDistance(s1: String, s2: String) -> Int {
        let a1 = Array(s1)
        let a2 = Array(s2)
        
        if a1.isEmpty { return a2.count }
        if a2.isEmpty { return a1.count }
        
        var lastRow = [Int](0...s2.count)
        var currentRow = [Int](repeating: 0, count: s2.count + 1)
        
        for i in 1...a1.count {
            currentRow[0] = i
            for j in 1...a2.count {
                let cost = a1[i - 1] == a2[j - 1] ? 0 : 1
                currentRow[j] = min(
                    currentRow[j - 1] + 1, // Insertion
                    lastRow[j] + 1,        // Deletion
                    lastRow[j - 1] + cost  // Substitution
                )
            }
            lastRow = currentRow
        }
        return lastRow[s2.count]
    }
}

// MARK: - String helper
extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        self.range(of: other, options: .caseInsensitive, locale: .current) != nil
    }
}

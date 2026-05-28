import Foundation

public struct CSVParser {
    public static func parse(
        text: String,
        delimiter: Character = ",",
        skipStartLines: Int = 0,
        skipEndLines: Int = 0
    ) -> [[String]] {
        var lines: [String] = []
        text.enumerateLines { line, _ in
            lines.append(line)
        }
        
        if skipStartLines > 0 && skipStartLines < lines.count {
            lines.removeFirst(skipStartLines)
        }
        
        if skipEndLines > 0 && skipEndLines < lines.count {
            lines.removeLast(skipEndLines)
        }
        
        var result: [[String]] = []
        for line in lines {
            let row = parseLine(line, delimiter: delimiter)
            // Skip purely empty lines
            if row.count > 1 || (row.count == 1 && !row[0].isEmpty) {
                result.append(row)
            }
        }
        return result
    }
    
    private static func parseLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if insideQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    currentField.append("\"")
                    i += 2
                    continue
                } else {
                    insideQuotes.toggle()
                }
            } else if char == delimiter && !insideQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
                currentField = ""
            } else {
                currentField.append(char)
            }
            i += 1
        }
        fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }
}

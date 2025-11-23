//
//  MarkdownRenderer.swift
//  TimePhotos
//
//  Enhanced Markdown rendering with proper styling
//

import SwiftUI
import AppKit

struct MarkdownText: View {
    let markdown: String
    let isUser: Bool
    let baseFontSize: CGFloat = 14
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdown(), id: \.id) { block in
                block.view(isUser: isUser, baseFontSize: baseFontSize)
            }
        }
    }
    
    private func parseMarkdown() -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var currentParagraph: [String] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var codeBlockLanguage: String = ""
        var inList = false
        var listItems: [String] = []
        var isOrderedList = false
        var inTable = false
        var tableRows: [[String]] = []
        var tableHeaders: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for code block start/end
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    blocks.append(.codeBlock(content: codeBlockContent.joined(separator: "\n"), language: codeBlockLanguage))
                    codeBlockContent = []
                    codeBlockLanguage = ""
                    inCodeBlock = false
                } else {
                    // Start code block
                    if !currentParagraph.isEmpty {
                        blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                        currentParagraph = []
                    }
                    if inList {
                        blocks.append(.list(items: listItems, ordered: isOrderedList))
                        listItems = []
                        inList = false
                    }
                    codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }
            
            // Check for headers (1-6 # symbols)
            if trimmed.hasPrefix("#") {
                let headerPrefix = trimmed.prefix(while: { $0 == "#" })
                if headerPrefix.count <= 6 && headerPrefix.count > 0 {
                    if !currentParagraph.isEmpty {
                        blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                        currentParagraph = []
                    }
                    if inList {
                        blocks.append(.list(items: listItems, ordered: isOrderedList))
                        listItems = []
                        inList = false
                    }
                    let level = headerPrefix.count
                    let content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        blocks.append(.heading(level: level, content: content))
                    }
                    continue
                }
            }
            
            // Check for table separator row (contains | and -)
            let isTableSeparator = trimmed.contains("|") && trimmed.contains("-") && trimmed.range(of: #"\|[\s-]+\|"#, options: .regularExpression) != nil
            
            // Check for table row (contains |)
            let isTableRow = trimmed.contains("|") && !isTableSeparator
            
            if isTableRow {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                    currentParagraph = []
                }
                if inList {
                    blocks.append(.list(items: listItems, ordered: isOrderedList))
                    listItems = []
                    inList = false
                }
                
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if !inTable {
                    // First row is header
                    tableHeaders = cells
                    inTable = true
                    tableRows = []
                } else {
                    tableRows.append(cells)
                }
                continue
            }
            
            if isTableSeparator {
                // This is the separator row, continue building table
                continue
            }
            
            // End table if we were in one and hit a non-table line
            if inTable {
                blocks.append(.table(headers: tableHeaders, rows: tableRows))
                tableHeaders = []
                tableRows = []
                inTable = false
            }
            
            // Check for horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" || (trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }) {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                    currentParagraph = []
                }
                if inList {
                    blocks.append(.list(items: listItems, ordered: isOrderedList))
                    listItems = []
                    inList = false
                }
                blocks.append(.horizontalRule)
                continue
            }
            
            // Check for list items
            let listPattern = #"^[\s]*[-*+]\s+(.+)$"#
            let orderedListPattern = #"^[\s]*\d+\.\s+(.+)$"#
            
            if let regex = try? NSRegularExpression(pattern: listPattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
               match.numberOfRanges > 1 {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                    currentParagraph = []
                }
                if inList && isOrderedList {
                    blocks.append(.list(items: listItems, ordered: true))
                    listItems = []
                }
                inList = true
                isOrderedList = false
                let contentRange = match.range(at: 1)
                if let range = Range(contentRange, in: trimmed) {
                    listItems.append(String(trimmed[range]))
                }
                continue
            }
            
            if let regex = try? NSRegularExpression(pattern: orderedListPattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
               match.numberOfRanges > 1 {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                    currentParagraph = []
                }
                if inList && !isOrderedList {
                    blocks.append(.list(items: listItems, ordered: false))
                    listItems = []
                }
                inList = true
                isOrderedList = true
                let contentRange = match.range(at: 1)
                if let range = Range(contentRange, in: trimmed) {
                    listItems.append(String(trimmed[range]))
                }
                continue
            }
            
            // Empty line - paragraph break
            if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
                    currentParagraph = []
                }
                if inList {
                    blocks.append(.list(items: listItems, ordered: isOrderedList))
                    listItems = []
                    inList = false
                }
                continue
            }
            
            // Regular line - add to current paragraph
            currentParagraph.append(line)
        }
        
        // Add remaining content
        if !currentParagraph.isEmpty {
            blocks.append(.paragraph(content: currentParagraph.joined(separator: "\n")))
        }
        if inList && !listItems.isEmpty {
            blocks.append(.list(items: listItems, ordered: isOrderedList))
        }
        if inTable {
            blocks.append(.table(headers: tableHeaders, rows: tableRows))
        }
        
        return blocks.isEmpty ? [.paragraph(content: markdown)] : blocks
    }
}

enum MarkdownBlock: Identifiable {
    case paragraph(content: String)
    case heading(level: Int, content: String)
    case list(items: [String], ordered: Bool)
    case codeBlock(content: String, language: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    
    var id: String {
        switch self {
        case .paragraph(let content):
            return "p-\(content.prefix(20).hashValue)"
        case .heading(let level, let content):
            return "h\(level)-\(content.prefix(20).hashValue)"
        case .list(let items, let ordered):
            return "li-\(ordered ? "o" : "u")-\(items.count)-\(items.first?.prefix(10).hashValue ?? 0)"
        case .codeBlock(let content, _):
            return "code-\(content.prefix(20).hashValue)"
        case .table(let headers, let rows):
            return "table-\(headers.count)-\(rows.count)-\(headers.first?.prefix(10).hashValue ?? 0)"
        case .horizontalRule:
            return "hr-\(UUID().uuidString)"
        }
    }
    
    @ViewBuilder
    func view(isUser: Bool, baseFontSize: CGFloat) -> some View {
        switch self {
        case .paragraph(let content):
            MarkdownParagraph(text: content, isUser: isUser, baseFontSize: baseFontSize)
            
        case .heading(let level, let content):
            MarkdownHeading(text: content, level: level, isUser: isUser)
            
        case .list(let items, let ordered):
            MarkdownList(items: items, ordered: ordered, isUser: isUser, baseFontSize: baseFontSize)
            
        case .codeBlock(let content, _):
            CodeBlockView(content: content, isUser: isUser)
            
        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows, isUser: isUser, baseFontSize: baseFontSize)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }
}

struct MarkdownParagraph: View {
    let text: String
    let isUser: Bool
    let baseFontSize: CGFloat
    
    var body: some View {
        // Use AttributedString with Markdown support for inline formatting
        if let attributedString = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: baseFontSize))
                .foregroundColor(isUser ? .white : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.system(size: baseFontSize))
                .foregroundColor(isUser ? .white : .primary)
                .textSelection(.enabled)
        }
    }
}

struct MarkdownHeading: View {
    let text: String
    let level: Int
    let isUser: Bool
    
    var body: some View {
        let fontSize: CGFloat = {
            switch level {
            case 1: return 24
            case 2: return 20
            case 3: return 18
            case 4: return 16
            case 5: return 15
            default: return 14
            }
        }()
        
        let fontWeight: Font.Weight = level <= 2 ? .bold : .semibold
        
        // Use AttributedString with Markdown support for inline formatting in headings
        if let attributedString = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(isUser ? .white : .primary)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(isUser ? .white : .primary)
                .textSelection(.enabled)
        }
    }
}

struct MarkdownList: View {
    let items: [String]
    let ordered: Bool
    let isUser: Bool
    let baseFontSize: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: baseFontSize, weight: .medium))
                        .foregroundColor(isUser ? .white.opacity(0.8) : .secondary)
                        .frame(width: ordered ? 24 : 12, alignment: .trailing)
                    
                    if let attributedString = try? AttributedString(markdown: item, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributedString)
                            .font(.system(size: baseFontSize))
                            .foregroundColor(isUser ? .white : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(item)
                            .font(.system(size: baseFontSize))
                            .foregroundColor(isUser ? .white : .primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct CodeBlockView: View {
    let content: String
    let isUser: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isUser ? .white.opacity(0.9) : .primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUser ? Color.white.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                )
        }
    }
}

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]
    let isUser: Bool
    let baseFontSize: CGFloat
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        VStack(alignment: .leading, spacing: 0) {
                            if let attributedString = try? AttributedString(markdown: header, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                Text(attributedString)
                                    .font(.system(size: baseFontSize, weight: .semibold))
                                    .foregroundColor(isUser ? .white : .primary)
                                    .textSelection(.enabled)
                            } else {
                                Text(header)
                                    .font(.system(size: baseFontSize, weight: .semibold))
                                    .foregroundColor(isUser ? .white : .primary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 100, alignment: .leading)
                        .background(isUser ? Color.white.opacity(0.2) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                        
                        if index < headers.count - 1 {
                            Divider()
                                .frame(width: 1)
                                .background(Color.secondary.opacity(0.3))
                        }
                    }
                }
                .background(isUser ? Color.white.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                
                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            VStack(alignment: .leading, spacing: 0) {
                                if let attributedString = try? AttributedString(markdown: cell, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                    Text(attributedString)
                                        .font(.system(size: baseFontSize))
                                        .foregroundColor(isUser ? .white.opacity(0.9) : .primary)
                                        .textSelection(.enabled)
                                } else {
                                    Text(cell)
                                        .font(.system(size: baseFontSize))
                                        .foregroundColor(isUser ? .white.opacity(0.9) : .primary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 100, alignment: .leading)
                            .background(rowIndex % 2 == 0 ? (isUser ? Color.white.opacity(0.1) : Color.clear) : (isUser ? Color.white.opacity(0.05) : Color(NSColor.controlBackgroundColor).opacity(0.3)))
                            
                            if colIndex < row.count - 1 {
                                Divider()
                                    .frame(width: 1)
                                    .background(Color.secondary.opacity(0.2))
                            }
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUser ? Color.white.opacity(0.3) : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

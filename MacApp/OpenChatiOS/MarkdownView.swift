import SwiftUI

// Simple, reliable markdown: paragraph text via AttributedString, fenced code as CodeBlock.
// No nested frames that fight layout — each block is a plain VStack element.

struct MarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parseBlocks(text)) { block in
                switch block.kind {
                case .paragraph(let s): InlineMD(s)
                case .code(let lang, let code): CodeBlock(lang: lang, code: code)
                case .table(let rows): TableBlock(rows: rows)
                }
            }
        }
    }
}

private struct InlineMD: View {
    let source: String
    init(_ s: String) { source = s }
    var body: some View {
        Text(attributed)
            .font(.system(size: 14.5))
            .lineSpacing(5)
            .textSelection(.enabled)
    }
    var attributed: AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let a = try? AttributedString(markdown: source, options: opts) { return a }
        return AttributedString(source)
    }
}

private struct CodeBlock: View {
    let lang: String
    let code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted).textCase(.uppercase)
                Spacer()
                Button(copied ? "Copied ✓" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .font(.system(size: 11)).foregroundColor(Theme.accent).buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.surface)
            Divider().opacity(0.6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).padding(12)
            }
        }
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }
}

private struct TableBlock: View {
    let rows: [[String]]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        InlineMD(cell).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(idx == 0 ? Theme.accentSoft : Color.clear)
                    }
                }
                if idx < rows.count - 1 { Divider().opacity(0.5) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }
}

// ── Parser ──
struct MDBlock: Identifiable { let id: Int; let kind: Kind
    enum Kind { case paragraph(String), code(lang: String, code: String), table(rows: [[String]]) }
}

func parseBlocks(_ text: String) -> [MDBlock] {
    var out: [MDBlock] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0, para: [String] = []
    func append(_ kind: MDBlock.Kind) { out.append(MDBlock(id: out.count, kind: kind)) }
    func flush() { if !para.isEmpty { append(.paragraph(para.joined(separator: "\n"))); para = [] } }
    while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") {
            flush()
            let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var code: [String] = []; i += 1
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
            append(.code(lang: lang, code: code.joined(separator: "\n"))); i += 1; continue
        }
        if t.hasPrefix("|") && t.hasSuffix("|") {
            var rows: [[String]] = []; var j = i
            while j < lines.count {
                let u = lines[j].trimmingCharacters(in: .whitespaces)
                if u.hasPrefix("|") {
                    if u.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "|", with: "").allSatisfy({ $0 == "-" || $0 == ":" }) { j += 1; continue }
                    let cells = u.dropFirst().dropLast().split(
                        separator: "|",
                        omittingEmptySubsequences: false
                    ).map { $0.trimmingCharacters(in: .whitespaces) }
                    rows.append(cells); j += 1
                } else { break }
            }
            if rows.count >= 2 { flush(); append(.table(rows: rows)); i = j; continue }
        }
        para.append(lines[i]); i += 1
    }
    flush()
    if out.isEmpty { append(.paragraph(text)) }
    return out
}

import Foundation

// MARK: - TF-IDF Search Engine (pure Swift)

final class SearchEngine {

    static let shared = SearchEngine()

    private var documents: [SearchResult] = []
    private var invertedIndex: [String: [(docIndex: Int, tf: Double)]] = [:]
    private var idfScores: [String: Double] = [:]
    private var indexed = false

    private let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "is", "was", "are", "be",
        "this", "that", "it", "its", "as", "up", "if",
    ]

    // MARK: - Public API

    /// Rebuild the index from all files in watched folders.
    func reindex(watchURLs: [URL]) {
        var docs: [SearchResult] = []
        let fm = FileManager.default

        for base in watchURLs {
            guard let folders = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for folder in folders {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: folder.path, isDirectory: &isDir)
                guard isDir.boolValue, !folder.lastPathComponent.hasPrefix(".") else { continue }

                guard let files = try? fm.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]) else { continue }

                for file in files {
                    var fileIsDir: ObjCBool = false
                    fm.fileExists(atPath: file.path, isDirectory: &fileIsDir)
                    guard !fileIsDir.boolValue else { continue }

                    docs.append(SearchResult(
                        fileName: file.lastPathComponent,
                        folder:   folder.lastPathComponent,
                        path:     file,
                        ext:      file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)",
                        score:    0
                    ))
                }
            }
        }

        buildIndex(docs)
    }

    func search(query: String, maxResults: Int = 10) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var scores = [Int: Double](minimumCapacity: documents.count)

        // TF-IDF cosine similarity
        for token in queryTokens {
            guard let postings = invertedIndex[token],
                  let idf = idfScores[token] else { continue }
            let queryWeight = idf
            for posting in postings {
                let docWeight = posting.tf * idf
                scores[posting.docIndex, default: 0] += queryWeight * docWeight
            }
        }

        let q = query.lowercased()

        // Keyword boost (exact substring matches on filename / folder)
        for (i, doc) in documents.enumerated() {
            let fname = doc.fileName.lowercased()
            let folder = doc.folder.lowercased()

            if fname.hasPrefix(q)        { scores[i] = max(scores[i, default: 0], 0.90) }
            else if fname.contains(q)    { scores[i] = max(scores[i, default: 0], 0.70) }
            else if folder.contains(q)   { scores[i] = max(scores[i, default: 0], 0.30) }

            // Word boundary match
            for word in q.split(separator: " ") {
                let w = String(word)
                if fname.contains(w)     { scores[i] = max(scores[i, default: 0], 0.50) }
            }
        }

        // Build results, normalize scores
        let maxScore = scores.values.max() ?? 1.0
        let results: [SearchResult] = scores
            .filter { $0.value > 0.02 }
            .sorted { $0.value > $1.value }
            .prefix(maxResults)
            .compactMap { idx, rawScore -> SearchResult? in
                guard idx < documents.count else { return nil }
                let doc = documents[idx]
                let normalized = min(1.0, rawScore / max(maxScore, 1.0))
                return SearchResult(fileName: doc.fileName, folder: doc.folder,
                                    path: doc.path, ext: doc.ext, score: normalized)
            }

        return results
    }

    // MARK: - Internals

    private func buildIndex(_ docs: [SearchResult]) {
        documents = docs
        invertedIndex = [:]
        idfScores = [:]

        let N = Double(docs.count)
        var termDocFreq: [String: Int] = [:]
        var docTermFreqs: [[String: Double]] = Array(repeating: [:], count: docs.count)

        for (i, doc) in docs.enumerated() {
            let text = "\(doc.fileName) \(doc.folder)"
            let tokens = tokenize(text)
            var freq: [String: Int] = [:]
            for token in tokens { freq[token, default: 0] += 1 }
            let maxFreq = Double(freq.values.max() ?? 1)
            for (term, count) in freq {
                docTermFreqs[i][term] = Double(count) / maxFreq   // normalized TF
                termDocFreq[term, default: 0] += 1
            }
        }

        // Build inverted index
        for (i, termFreqs) in docTermFreqs.enumerated() {
            for (term, tf) in termFreqs {
                invertedIndex[term, default: []].append((docIndex: i, tf: tf))
            }
        }

        // IDF scores
        for (term, df) in termDocFreq {
            idfScores[term] = log(N / Double(df) + 1)
        }

        indexed = true
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }
}

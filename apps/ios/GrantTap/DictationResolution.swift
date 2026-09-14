import Foundation

extension Dictator {
    static func resolvedTranscript(
        candidates: [String: DictationCandidate], preferredLanguage: String?
    ) -> (text: String, language: String)? {
        guard let best = candidates.max(by: {
            candidateScore(
                text: $0.value.text, confidences: $0.value.words.map(\.confidence),
                language: $0.key, preferredLanguage: preferredLanguage
            ) < candidateScore(
                text: $1.value.text, confidences: $1.value.words.map(\.confidence),
                language: $1.key, preferredLanguage: preferredLanguage
            )
        }) else { return nil }
        var text = best.value.text
        let alternateLanguage = best.key == "ru-RU" ? "en-US" : "ru-RU"
        if let alternate = candidates[alternateLanguage] {
            text = mergeWords(
                base: best.value.words, language: best.key,
                alternate: alternate.words
            )
        }
        return (
            VoiceTextNormalizer.normalize(text),
            best.key.hasPrefix("ru") ? "RU" : "EN"
        )
    }

    static func candidateScore(
        text: String, confidences: [Float], language: String,
        preferredLanguage: String?
    ) -> Double {
        let confidence = confidences.isEmpty ? 0 :
            confidences.reduce(0) { $0 + Double($1) } / Double(confidences.count)
        let scalars = text.unicodeScalars
        let letters = max(1, scalars.filter { CharacterSet.letters.contains($0) }.count)
        let cyrillic = scalars.filter { (0x0400...0x052F).contains(Int($0.value)) }.count
        let latin = scalars.filter {
            (0x0041...0x005A).contains(Int($0.value)) ||
                (0x0061...0x007A).contains(Int($0.value))
        }.count
        let scriptFit = language.hasPrefix("ru") ? Double(cyrillic) / Double(letters)
            : Double(latin) / Double(letters)
        let preferred = language == preferredLanguage ? 0.025 : 0
        return confidence + scriptFit * 0.38 + preferred
    }

    static func mergeWords(
        base: [DictationWord], language: String, alternate: [DictationWord]
    ) -> String {
        guard language.hasPrefix("ru") else {
            return base.map(\.text).joined(separator: " ")
        }
        return base.map { baseWord -> String in
            let end = baseWord.start + baseWord.duration
            let overlaps = alternate.filter { word in
                let otherEnd = word.start + word.duration
                return min(end, otherEnd) - max(baseWord.start, word.start) > 0
            }
            let english = overlaps.map(\.text).joined(separator: " ")
            let confidence = overlaps.map(\.confidence).max() ?? 0
            if VoiceTextNormalizer.isKnownTechnology(english),
               confidence >= max(0.25, baseWord.confidence - 0.08) {
                return VoiceTextNormalizer.normalize(english)
            }
            return baseWord.text
        }.joined(separator: " ")
    }
}

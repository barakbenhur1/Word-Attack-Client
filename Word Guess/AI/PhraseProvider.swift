//
//  PhraseProvider.swift
//  WordZap
//
//  Created by Barak Ben Hur on 31/08/2025.
//

//  BossPhraseProvider.swift

import SwiftUI

@Observable
final class PhraseProvider: ObservableObject {
    
    private let showPhraseTime: UInt64 = 10_000_000_000
    private let hidePhraseTime: UInt64 = 6_000_000_000
    
    private var blocked: Bool
    private var currentPhrase: String
    
    private var timer: Timer?
    
    private var didStartShowing: Bool
    private var showPhrase: Bool = false {
        didSet {
            if showPhrase { currentPhrase = nextPhrase() }
            guard !blocked else { return blocked = false }
            Task.detached(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: showPhrase ? showPhraseTime : hidePhraseTime)
                withAnimation { self.showPhrase.toggle() }
            }
        }
    }
    
    var phrase: String { currentPhrase.localized }
    
    var showPhraseValue: Bool { showPhrase }
    
    init() {
        didStartShowing = false
        blocked = false
        currentPhrase = ""
    }
    
    // MARK: - Public
    
    func startShowingPhrase() {
        guard !didStartShowing else { return }
        didStartShowing = true
        blocked = false
        showPhrase = true
    }
    
    func hidePhrase() {
        blocked = true
        showPhrase = false
    }
    
    private func pushOnce() async {
        let text = nextPhrase()
        await SharedStore.writeAITooltipAsync(text)
        await MainActor.run { SharedStore.requestWidgetReload() }
    }
    
    func stop() { timer?.invalidate(); timer = nil }
    
    /// Start rotating phrases (you choose the cadence).
    func startPushingPhrases(every seconds: TimeInterval = 60) {
        timer?.invalidate()
        // Fire immediately once so the widget updates right away.
        Task.detached { @MainActor [weak self] in
            guard let self else { return }
            await pushOnce()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task.detached { @MainActor [weak self] in
                guard let self else { return }
                await pushOnce()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    enum BossPersonality: CaseIterable {
        case smartyPants
        case taunting
        case confident
        case nerdy
    }
    
    // MARK: - State
    private var history: [BossPersonality] = []
    private let maxStreak = 3   // hard cap streak length
    
    // MARK: - Phrase Pools
    
    // MARK: - Word Zap Boss Phrases
    
    private let smartyPantsPhrases = [
        "Grammar 101",
        "Weak syntax",
        "Pathetic lexicon",
        "Read a book",
        "Big word, small brain",
        "Orthography fail",
        "Declined!",
        "Conjugated!",
        "Semantics win",
        "Dictionary > you",
        "Tiny lexicon",
        "Lacking etymology",
        "Wordless wonder",
        "Syntax error",
        "Morphology meltdown",
        "Case closed",
        "Spellcheck champ (not you)",
        "Phonetics fail",
        "Logophile? Doubtful",
        "Lexiconless",
        "You skipped linguistics",
        "Try phonology next time",
        "Misplaced modifier",
        "Split infinitive!",
        "Dangling participle",
        "Clause collapse",
        "Sentence fragment",
        "Run-on alert",
        "Punctuation panic",
        "Comma catastrophe",
        "Capitalization chaos",
        "Apostrophe abuse",
        "Subject–verb mismatch",
        "Agreement error",
        "Typo tyrant wins",
        "Grammar goblin strikes",
        "Linguist laughs last",
        "Spelling snob approved",
        "Diction disaster",
        "Alphabet assassin",
        "Proofread, peasant",
        "Vocab vacuum",
        "Word bank bankrupt",
        "Error-prone editor",
        "Syntax sorcery",
        "Semantic supremacy",
        "Pedant prevails",
        "Verbal void",
        "Your grammar is cringe",
        "Language dropout",
        "Lexical loser",
        "Speechless already",
        "Illiterate much?",
        "Failed linguist",
        "Dictionary dropout",
        "Pathetic pedagogy",
        "Grammar geek wins",
        "Schoolyard spelling bee fail"
    ]
    
    private let tauntingPhrases = [
        "Embarrassing",
        "Outclassed",
        "Child’s play",
        "Predictable",
        "Too slow",
        "Wrong again",
        "Nice fail",
        "Zap!",
        "Fail faster",
        "Puny vocab",
        "Try harder",
        "Basic",
        "Weak guess",
        "Pathetic play",
        "Is that all?",
        "Laughable",
        "Guess harder",
        "Nice try… not",
        "Again? Really?",
        "Hopeless",
        "Keep guessing",
        "Swing and miss",
        "Not even close",
        "Boring",
        "Sad effort",
        "Zapped again",
        "Repeat failure",
        "Fumbling",
        "Epic fail",
        "Pathetic try",
        "Too easy",
        "Sloppy",
        "Ridiculous",
        "Mediocre",
        "Try literacy",
        "Missed again",
        "Unworthy",
        "You wish",
        "Desperate much?",
        "Zero effort",
        "Facepalm",
        "Shameful",
        "Guesswork trash",
        "Zap zap",
        "C’mon already",
        "Give up yet?",
        "Still wrong",
        "Always wrong",
        "Clueless",
        "Loser energy",
        "No brains",
        "Amateur hour",
        "Trash guess",
        "Sloppy mess",
        "No match",
        "Word weakling",
        "Guess goblin",
        "Wrongling"
    ]
    
    private let confidentPhrases = [
        "I eat words",
        "Out of your league",
        "You can’t win",
        "Hopeless case",
        "Futile",
        "Don’t bother",
        "Dominated",
        "Crushed",
        "Defeated already",
        "Just quit",
        "This is mine",
        "Easy mode",
        "Owned",
        "Bow before me",
        "Your end",
        "Not even close",
        "No contest",
        "Pathetic effort",
        "Game over",
        "My victory",
        "Schooled",
        "Destroyer of words",
        "Absolute",
        "Invincible",
        "Inevitable",
        "I always win",
        "Hopeless fool",
        "Inferior",
        "Outplayed",
        "Checkmate",
        "Dominion",
        "Word king",
        "Mastermind",
        "Crown mine",
        "Champion here",
        "Top tier",
        "Final word",
        "Alpha words",
        "Supreme",
        "Forever winner",
        "Flawless",
        "No chance",
        "Elite only",
        "Hopeless mortal",
        "Conquered",
        "Zap lord",
        "I reign",
        "Undefeated",
        "Surrender now",
        "Your loss",
        "Bow down",
        "Feast of victory",
        "Final strike",
        "Nothing personal",
        "Trivial win",
        "No sweat",
        "Game’s mine",
        "Words obey me",
        "Crowned champ"
    ]
    
    private let nerdyDeepCutPhrases = [
        "Hapax fail",
        "Rare word, rarer win",
        "Lexeme lost",
        "Clause collapse",
        "Parsing error",
        "Syntax tree snapped",
        "Grammar goblin wins",
        "Etymology expert",
        "Obsolete usage!",
        "Your tense is wrong",
        "Plural? Wrong!",
        "Declension denied",
        "Case mismatch",
        "Conjugation crusher",
        "Semantics slayer",
        "Pragmatics prevail",
        "Orthography overlord",
        "Phoneme fail",
        "Morpheme master",
        "Vocabulary vacuum",
        "Diachronic disaster",
        "IPA master here",
        "Stress pattern slip",
        "Accent misplaced",
        "Loanword lost",
        "Hybrid horror",
        "Nonce word nonsense",
        "Derivation denied",
        "Inflection infection",
        "Polysyllabic panic",
        "Register mismatch",
        "Idiom idiot",
        "Cognate crash",
        "Neologism noob",
        "Eponym error",
        "Jargon jammed",
        "Buzzword busted",
        "Semantic drift",
        "Morph master",
        "Syntax sorcerer",
        "Linguist legend",
        "Pedant power",
        "Grammar gremlin",
        "Affix annihilated",
        "Root rot",
        "Compound crushed",
        "Corpora conqueror",
        "Parse-tree prince",
        "Declension dragon",
        "Syntax skeleton",
        "Linguist lord",
        "Verb vanquisher",
        "Adjective annihilator",
        "Preposition predator",
        "Phonetics phantom",
        "Lexicon overlord",
        "Inflection invader",
        "Semantics sovereign",
        "Morph moron detected",
        "Pragmatics punisher"
    ]
    
    // MARK: - Public API
    
    func nextPhrase() -> String {
        let personality = pickNextPersonality()
        history.append(personality)
        return phrase(for: personality)
    }
    
    func phrase(for personality: BossPersonality) -> String {
        switch personality {
        case .smartyPants: return smartyPantsPhrases.randomElement() ?? "..."
        case .taunting:    return tauntingPhrases.randomElement() ?? "..."
        case .confident:   return confidentPhrases.randomElement() ?? "..."
        case .nerdy:       return nerdyDeepCutPhrases.randomElement() ?? "..."
        }
    }
    
    // MARK: - Private
    
    private func pickNextPersonality() -> BossPersonality {
        let all = BossPersonality.allCases
        
        if let last = history.last {
            // count consecutive streak of the same personality
            let streak = history.reversed().prefix(while: { $0 == last }).count
            
            if streak >= maxStreak {
                // force a change
                return all.filter { $0 != last }.randomElement() ?? last
            }
        }
        
        // otherwise just pick random
        return all.randomElement() ?? .taunting
    }
}

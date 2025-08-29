//
//  WordleViewModel.swift
//  Word Guess
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI

/// Little helper for UI/testing (not used by core engine).
public func generateWord(for lang: Language, length: Int = 5) -> String {
    let en = Array("abcdefghijklmnopqrstuvwxyz")
    let he = Array("אבגדהוזחטיכלמנסעפצקרשת")
    let alpha = (lang == .en) ? en : he
    return (0..<length).compactMap { _ in alpha.randomElement() }.map(String.init).joined()
}

@MainActor
@Observable
class WordleAIViewModel {
    // MARK: - Private Parameters
    private let lang: Language
    private var history: [GuessHistory]
    private var solverWarmedup: Bool = false
    
    private let showPhraseTime: UInt64 = 10_000_000_000
    private let hidePhraseTime: UInt64 = 6_000_000_000
    
    private var blocked: Bool
    private var currentPhrase: String = ""
    
    private var didStartShowing: Bool
    private var showPhrase: Bool = false {
        didSet {
            if showPhrase { currentPhrase = PhraseProvider.shared.nextPhrase() }
            guard !blocked else { return blocked = false }
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: showPhrase ? showPhraseTime : hidePhraseTime)
                withAnimation { self.showPhrase.toggle() }
            }
        }
    }
    
    private var bossProvider: (() -> String?) = { nil } {
        didSet {
            Task.detached(priority: .high) { [weak self] in
                guard let self else { return }
                await solver().installBossEnhancementProvider(bossProvider)
            }
        }
    }
    
    // MARK: - Public Parameters
    var isReadyToGuess: Bool { solverWarmedup }
    
    var phrase: String { currentPhrase.localized }
    
    var showPhraseValue: Bool { showPhrase }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang = language
        history = startingHistory
        solverWarmedup = WordleAIProvider.aiWarmedup
        didStartShowing = false
        blocked = false
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard !solverWarmedup  else { return }
            await solver().warmUp()
            solverWarmedup = true
        }
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
    
    func manageMemory(with guessHistory: [GuessHistory] = [], provider: @escaping (() -> String?) = { nil }) {
        bossProvider = provider
        history = guessHistory
    }
    
    func addDetachedFirstGuess(with formatter: @escaping (_ value: String) -> GuessHistory?) {
        Task(priority: .high) { [weak self] in
            guard let self else { return }
            guard let guess = try? await solver().pickFirstGuessFromModel(lang: lang) else { return }
            guard let formattedGuess = formatter(guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined()) else { return }
            saveToHistory(guess: formattedGuess)
        }
    }
    
    func saveToHistory(guess: GuessHistory) { history.append(guess) }
    
    func deassign() { WordleAIProvider.shared.deassign() }
    
    // MARK: - Private
    
    private func solver() async -> WordleAI { await WordleAIProvider.shared.sharedAsync() }
    
    private func fallbackGuess() -> String { return generateWord(for: lang, length: 5) }
    
    func getFeedback(with difficulty: AIDifficulty) async -> String {
        let task = Task.detached(priority: .high) { [weak self] () -> String in
            do {
                guard let self else { fatalError("Solver is not avilbale") }
                return try await solver().guessNext(history: history,
                                                    lang: lang,
                                                    difficulty: difficulty)
                
            } catch { fatalError("Solver faild to provide a guess") }
        }
        
        return await task.value
    }
}

//  BossPhraseProvider.swift

final class PhraseProvider: Singleton {
    
    enum BossPersonality: CaseIterable {
        case smartyPants
        case taunting
        case confident
        case nerdy
    }
    
    // MARK: - Singleton
    private override init() {}
    
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

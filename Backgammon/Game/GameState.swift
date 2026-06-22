// GameState.swift
// Observable game state manager connecting the engine to the SwiftUI views.

import Foundation
import Combine

enum GamePhase {
    case initial          // Waiting for first roll to determine who goes first
    case rolling          // Player needs to roll
    case moving           // Player is selecting / making moves
    case aiTurn           // AI is computing / animating its turn
    case gameOver(GameResult)
}

enum InputMode: String, CaseIterable {
    case checkerFirst = "checker"
    case diceFirst    = "dice"
    var label: String {
        self == .checkerFirst ? "Checker-first" : "Dice-first"
    }
}

@MainActor
final class GameState: ObservableObject {

    // MARK: - Published state

    @Published var board = BackgammonBoard.initial
    @Published var currentPlayer: Player = .white   // White always goes first for simplicity
    @Published var phase: GamePhase = .rolling
    @Published var dice: [Int] = []
    @Published var usedDice: [Bool] = []            // Tracks which dice slots are consumed
    @Published var selectedPoint: Int? = nil        // checker-first: selected source (0-23 or 24=bar)
    @Published var selectedDieIndex: Int? = nil     // dice-first: selected die slot
    @Published var validDestinations: Set<Int> = [] // 0-23 or 24 (bear-off)
    @Published var message: String = "White's turn — tap Roll"
    @Published var gameResult: GameResult? = nil
    /// Set after White completes a turn; drives the coaching sheet in the UI.
    @Published var coachingAnalysis: BackgammonEngine.MoveAnalysis? = nil

    // MARK: - Staged moves (Done/Undo)

    /// Board state with pending (uncommitted) moves applied.
    @Published var pendingBoard = BackgammonBoard.initial
    /// Each pending move paired with the die-slot index it consumed.
    private var pendingMoves: [(CheckerMove, Int)] = []

    // MARK: - Input mode

    @Published var inputMode: InputMode {
        didSet { UserDefaults.standard.set(inputMode.rawValue, forKey: UDKey.inputMode) }
    }

    // MARK: - AI Personality

    /// Current AI skill level in [0, 1].  Published so the UI can reflect it.
    @Published private(set) var aiSkill: Double

    /// When true, `aiSkill` is automatically adjusted each turn based on the
    /// player's demonstrated move quality (coaching analysis scores).
    @Published var isAdaptiveAI: Bool

    // Smoothed estimate of the player's strength (0 = beginner, 1 = expert).
    // Persisted across sessions so the AI starts calibrated to your history.
    private var playerRating: Double
    private var adaptiveTurnsAnalyzed: Int = 0

    // Fixed skill used when adaptive mode is off.
    private var fixedAISkill: Double

    // UserDefaults keys
    private enum UDKey {
        static let playerRating  = "bg.playerRating"
        static let fixedAISkill  = "bg.fixedAISkill"
        static let isAdaptiveAI  = "bg.isAdaptiveAI"
        static let inputMode     = "bg.inputMode"
    }

    // MARK: - Coaching turn context

    private var turnStartBoard = BackgammonBoard.initial
    private var turnDice: [Int] = []

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        let savedRating  = ud.object(forKey: UDKey.playerRating) as? Double ?? 0.50
        let savedFixed   = ud.object(forKey: UDKey.fixedAISkill) as? Double ?? 0.65
        let savedAdapt   = ud.object(forKey: UDKey.isAdaptiveAI) as? Bool   ?? true
        let modeRaw      = ud.string(forKey: UDKey.inputMode) ?? ""

        playerRating  = savedRating
        fixedAISkill  = savedFixed
        isAdaptiveAI  = savedAdapt
        inputMode     = InputMode(rawValue: modeRaw) ?? .checkerFirst

        // Start the first game at the skill appropriate to the player's last known rating.
        aiSkill = savedAdapt ? Self.targetAISkill(for: savedRating) : savedFixed
    }

    // MARK: - AI Personality API

    /// Returns a human-readable description of the current AI strength.
    var aiSkillLabel: String { Self.skillLabel(for: aiSkill) }

    /// Returns a human-readable description of the player's rating.
    var playerRatingLabel: String { Self.skillLabel(for: playerRating) }

    /// The player's smoothed performance rating (0-1), for display in the UI.
    var playerRatingValue: Double { playerRating }

    /// The number of turns the adaptive model has observed in this session.
    var adaptiveTurnsCount: Int { adaptiveTurnsAnalyzed }

    /// Sets a fixed difficulty and disables adaptive mode.
    func setFixedDifficulty(_ skill: Double) {
        fixedAISkill = min(1.0, max(0.0, skill))
        isAdaptiveAI = false
        aiSkill = fixedAISkill
        UserDefaults.standard.set(fixedAISkill, forKey: UDKey.fixedAISkill)
        UserDefaults.standard.set(false,        forKey: UDKey.isAdaptiveAI)
    }

    /// Enables adaptive mode; immediately adjusts skill to match player rating.
    func enableAdaptiveAI() {
        isAdaptiveAI = true
        aiSkill = Self.targetAISkill(for: playerRating)
        UserDefaults.standard.set(true, forKey: UDKey.isAdaptiveAI)
    }

    // MARK: - Player Actions

    func rollDice() {
        guard case .rolling = phase else { return }
        coachingAnalysis = nil
        turnStartBoard   = board
        pendingBoard     = board
        pendingMoves     = []
        let rolled = BackgammonEngine.rollDice()
        turnDice = rolled
        dice = rolled
        usedDice = Array(repeating: false, count: rolled.count)
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []

        let moves = BackgammonEngine.generateMoves(
            board: board, dice: remainingDice, isWhite: currentPlayer == .white)

        if moves.count == 1, moves[0].moves.isEmpty {
            message = "\(currentPlayer.rawValue) rolled \(diceString()) — no moves available!"
            advanceTurn()
        } else {
            phase = .moving
            message = inputMode == .diceFirst
                ? "\(currentPlayer.rawValue) rolled \(diceString()) — select a die"
                : "\(currentPlayer.rawValue) rolled \(diceString()) — select a checker"
        }
    }

    // MARK: - Checker-first input

    func selectPoint(_ index: Int) {
        guard case .moving = phase, inputMode == .checkerFirst else { return }
        let isWhite = currentPlayer == .white

        // Tapping a valid destination executes the staged move
        if let from = selectedPoint, validDestinations.contains(index) {
            executeMove(CheckerMove(from: from, to: index))
            return
        }

        // Select a checker owned by the current player (from pendingBoard)
        let hasChecker: Bool
        if index == 24 {
            hasChecker = isWhite ? pendingBoard.whiteBar > 0 : pendingBoard.blackBar > 0
        } else {
            hasChecker = isWhite ? pendingBoard.points[index] > 0 : pendingBoard.points[index] < 0
        }

        guard hasChecker else {
            selectedPoint = nil
            validDestinations = []
            return
        }

        selectedPoint = index
        validDestinations = computeDestinations(from: index)
    }

    // MARK: - Dice-first input

    func selectDie(_ i: Int) {
        guard case .moving = phase, inputMode == .diceFirst else { return }
        guard i < usedDice.count, !usedDice[i] else { return }

        if selectedDieIndex == i {
            selectedDieIndex = nil
            validDestinations = []
            message = "Select a die, then tap a point"
            return
        }

        selectedDieIndex = i
        let die = dice[i]
        let singles = BackgammonEngine.legalSingleMoves(
            board: pendingBoard, die: die, isWhite: currentPlayer == .white)
        validDestinations = Set(singles.map { $0.to })
        message = validDestinations.isEmpty ? "No moves with this die" : "Tap a destination"
    }

    func selectDestWithDie(_ destIndex: Int) {
        guard case .moving = phase, inputMode == .diceFirst else { return }

        let dieIdx: Int
        let die: Int
        if let sel = selectedDieIndex {
            dieIdx = sel
            die = dice[sel]
        } else {
            // Auto-select: try each remaining die
            guard let found = remainingDice.enumerated().first(where: { _, d in
                BackgammonEngine.legalSingleMoves(
                    board: pendingBoard, die: d, isWhite: currentPlayer == .white
                ).contains(where: { $0.to == destIndex })
            }) else { return }
            die = found.element
            // find its slot in the usedDice array
            guard let slot = zip(dice, usedDice).enumerated()
                .first(where: { !$0.element.1 && $0.element.0 == die })?.offset
            else { return }
            dieIdx = slot
        }

        // Find which checker can reach destIndex with this die
        let singles = BackgammonEngine.legalSingleMoves(
            board: pendingBoard, die: die, isWhite: currentPlayer == .white)
        guard let match = singles.first(where: { $0.to == destIndex }) else { return }

        executeMove(CheckerMove(from: match.from, to: destIndex), forcedDieIndex: dieIdx)
        selectedDieIndex = nil
    }

    // MARK: - Move execution (staged — applies to pendingBoard)

    func executeMove(_ move: CheckerMove, forcedDieIndex: Int? = nil) {
        guard case .moving = phase else { return }
        let isWhite = currentPlayer == .white

        let dieIdx: Int
        if let forced = forcedDieIndex {
            dieIdx = forced
        } else {
            guard let found = findDie(for: move, isWhite: isWhite) else { return }
            dieIdx = found
        }

        pendingBoard = BackgammonEngine.applyMove(move, to: pendingBoard, isWhite: isWhite)
        pendingMoves.append((move, dieIdx))
        usedDice[dieIdx] = true
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []

        // Check win on staged board — game over is unambiguous even before commit
        if let result = BackgammonEngine.gameResult(pendingBoard) {
            board = pendingBoard
            pendingMoves = []
            gameResult = result
            phase = .gameOver(result)
            message = result.description
            return
        }

        let rem = remainingDice
        if rem.isEmpty {
            message = "Tap Done to end your turn"
        } else {
            let moreMoves = BackgammonEngine.generateMoves(board: pendingBoard, dice: rem, isWhite: isWhite)
            if moreMoves.count == 1, moreMoves[0].moves.isEmpty {
                message = "No more moves — tap Done"
            } else {
                message = inputMode == .diceFirst
                    ? "Select a die, then tap a point (\(rem.count) left)"
                    : "Select a checker (\(rem.count) die\(rem.count == 1 ? "" : "s") left)"
            }
        }
    }

    // MARK: - Done / Undo

    func commitMoves() {
        guard case .moving = phase else { return }
        board = pendingBoard
        pendingMoves = []
        advanceTurn()
    }

    func undoLastMove() {
        guard case .moving = phase, !pendingMoves.isEmpty else { return }
        let (_, dieIdx) = pendingMoves.removeLast()
        usedDice[dieIdx] = false

        // Rebuild pending board by replaying the remaining staged moves from scratch
        var rebuilt = board
        for (mv, _) in pendingMoves {
            rebuilt = BackgammonEngine.applyMove(mv, to: rebuilt, isWhite: currentPlayer == .white)
        }
        pendingBoard = rebuilt
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []

        let rem = remainingDice
        if rem.isEmpty {
            message = "Tap Done to end your turn"
        } else {
            message = inputMode == .diceFirst
                ? "Select a die, then tap a point (\(rem.count) left)"
                : "Select a checker (\(rem.count) die\(rem.count == 1 ? "" : "s") left)"
        }
    }

    var canCommit: Bool {
        guard case .moving = phase else { return false }
        if remainingDice.isEmpty { return true }
        let moreMoves = BackgammonEngine.generateMoves(
            board: pendingBoard, dice: remainingDice, isWhite: currentPlayer == .white)
        return moreMoves.count == 1 && moreMoves[0].moves.isEmpty
    }

    var canUndo: Bool {
        guard case .moving = phase else { return false }
        return !pendingMoves.isEmpty
    }

    // MARK: - AI Turn

    func triggerAITurn() {
        guard currentPlayer == .black else { return }
        phase = .aiTurn
        message = "Black is thinking…"

        // Capture skill so adaptive updates mid-Task don't affect this turn's move.
        let capturedSkill = aiSkill

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s UX pause before showing roll

            let rolled = BackgammonEngine.rollDice()
            self.dice = rolled
            self.usedDice = Array(repeating: false, count: rolled.count)
            self.message = "Black rolled \(self.diceString()) — \(capturedSkill < 0.35 ? "plays…" : "thinking…")"

            // Snapshot board so the background task captures a value type, not self.
            let boardSnapshot = self.board

            // Run move selection on a background thread.
            let best = await Task.detached(priority: .userInitiated) {
                BackgammonEngine.chooseBestMove(board: boardSnapshot, dice: rolled,
                                               isWhite: false, skill: capturedSkill)
            }.value

            self.message = "Black plays"
            try? await Task.sleep(nanoseconds: 300_000_000)

            for move in best.moves {
                self.board = BackgammonEngine.applyMove(move, to: self.board, isWhite: false)
                try? await Task.sleep(nanoseconds: 420_000_000) // Animate each move
            }

            if let result = BackgammonEngine.gameResult(self.board) {
                self.gameResult = result
                self.phase = .gameOver(result)
                self.message = result.description
                return
            }

            self.advanceTurn()
        }
    }

    // MARK: - Helpers

    private func advanceTurn() {
        if currentPlayer == .white && board != turnStartBoard {
            let startBoard  = turnStartBoard
            let endBoard    = board
            let usedDiceArr = turnDice
            Task {
                let analysis = await Task.detached(priority: .userInitiated) {
                    BackgammonEngine.analyzePlayerTurn(
                        boardBefore: startBoard,
                        boardAfter:  endBoard,
                        dice:        usedDiceArr,
                        isWhite:     true
                    )
                }.value
                self.coachingAnalysis = analysis
                self.applyAdaptiveUpdate(from: analysis)
            }
        }

        currentPlayer = currentPlayer == .white ? .black : .white
        dice = []
        usedDice = []
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []
        pendingMoves = []

        if currentPlayer == .black {
            phase = .aiTurn
            triggerAITurn()
        } else {
            phase = .rolling
            message = "White's turn — tap Roll"
        }
    }

    /// Updates the player rating and AI skill from a completed coaching analysis.
    private func applyAdaptiveUpdate(from analysis: BackgammonEngine.MoveAnalysis) {
        guard isAdaptiveAI else { return }

        // Exponential moving average with a decaying learning rate:
        // fast early in a session, stabilises over time.
        let alpha = max(0.05, 0.30 / (1.0 + Double(adaptiveTurnsAnalyzed) * 0.04))
        playerRating = (1.0 - alpha) * playerRating + alpha * analysis.quality.performanceScore
        adaptiveTurnsAnalyzed += 1

        // Smoothly converge AI skill toward the target (avoids jarring mid-game jumps).
        let target = Self.targetAISkill(for: playerRating)
        aiSkill = 0.80 * aiSkill + 0.20 * target

        // Persist updated player rating.
        UserDefaults.standard.set(playerRating, forKey: UDKey.playerRating)
    }

    private var remainingDice: [Int] {
        zip(dice, usedDice).compactMap { (die, used) in used ? nil : die }
    }

    private func findDie(for move: CheckerMove, isWhite: Bool) -> Int? {
        let dieValue: Int
        if move.from == 24 {
            dieValue = isWhite ? (24 - move.to) : (move.to + 1)
        } else if move.to == 24 {
            // Bear-off: prefer exact match, then smallest overshoot
            let distance = isWhite ? (move.from + 1) : (24 - move.from)
            let rem = zip(dice, usedDice).enumerated().filter { !$0.element.1 }.map { ($0.offset, $0.element.0) }
            if let exact = rem.first(where: { $0.1 == distance }) { return exact.0 }
            if let over  = rem.filter({ $0.1 > distance }).min(by: { $0.1 < $1.1 }) { return over.0 }
            return nil
        } else {
            dieValue = abs(move.to - move.from)
        }
        return zip(dice, usedDice).enumerated()
            .first(where: { !$0.element.1 && $0.element.0 == dieValue })?.offset
    }

    private func computeDestinations(from source: Int) -> Set<Int> {
        let isWhite = currentPlayer == .white
        var dests = Set<Int>()
        var tried = Set<Int>()

        for die in remainingDice {
            guard !tried.contains(die) else { continue }
            tried.insert(die)
            let singles = BackgammonEngine.legalSingleMoves(board: pendingBoard, die: die, isWhite: isWhite)
            for m in singles where m.from == source {
                dests.insert(m.to)
            }
        }
        return dests
    }

    private func diceString() -> String {
        dice.map(String.init).joined(separator: " & ")
    }

    func newGame() {
        board = .initial
        pendingBoard = .initial
        pendingMoves = []
        currentPlayer = .white
        phase = .rolling
        dice = []
        usedDice = []
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []
        gameResult = nil
        coachingAnalysis = nil
        turnStartBoard = .initial
        turnDice = []
        message = "White's turn — tap Roll"

        adaptiveTurnsAnalyzed = 0
        aiSkill = isAdaptiveAI ? Self.targetAISkill(for: playerRating) : fixedAISkill
    }

    // MARK: - Static helpers

    /// Human-readable label for a skill value.
    static func skillLabel(for skill: Double) -> String {
        switch skill {
        case ..<0.20: return "Novice"
        case ..<0.40: return "Beginner"
        case ..<0.60: return "Intermediate"
        case ..<0.80: return "Advanced"
        case ..<0.95: return "Expert"
        default:      return "Master"
        }
    }

    /// AI skill target: always ~15 percentage points above the player's rating,
    /// so the AI stays challenging without being overwhelming.
    static func targetAISkill(for playerRating: Double) -> Double {
        min(1.0, max(0.15, playerRating + 0.15))
    }
}

// MARK: - MoveQuality performance score

extension BackgammonEngine.MoveQuality {
    /// Maps move quality to a [0, 1] performance score for adaptive rating updates.
    var performanceScore: Double {
        switch self {
        case .optimal:    return 1.00
        case .excellent:  return 0.82
        case .good:       return 0.62
        case .inaccuracy: return 0.40
        case .mistake:    return 0.20
        case .blunder:    return 0.00
        }
    }
}

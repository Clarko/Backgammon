import Foundation
import SwiftUI

// MARK: - Enums

enum Player { case white, black }

enum GamePhase: Equatable {
    case rolling
    case moving
    case aiTurn
    case gameOver
}

enum GameResult: Equatable {
    case win(isGammon: Bool, isBackgammon: Bool)
    case loss(isGammon: Bool, isBackgammon: Bool)
}

enum InputMode: String, CaseIterable {
    case checkerFirst = "checker"
    case diceFirst    = "dice"
    var label: String {
        switch self {
        case .checkerFirst: return "Checker-first"
        case .diceFirst:    return "Dice-first"
        }
    }
}

// MARK: - GameState

@MainActor
final class GameState: ObservableObject {

    // Board and turn
    @Published var board = BackgammonBoard.initial
    @Published var currentPlayer: Player = .white
    @Published var phase: GamePhase = .rolling
    @Published var dice: [Int] = []
    @Published var usedDice: [Bool] = []

    // Pending (staged) move state — pairs of (move, dieIndex used)
    @Published var pendingBoard = BackgammonBoard.initial
    @Published private(set) var pendingMoves: [(CheckerMove, Int)] = []

    // Selection state
    @Published var selectedPoint: Int?       // checker-first: selected source point (24 = bar)
    @Published var selectedDieIndex: Int?    // dice-first: which die slot is active
    @Published var validDestinations: Set<Int> = []

    // UI
    @Published var message: String = "Roll to start!"
    @Published var gameResult: GameResult? = nil
    @Published var coachingAnalysis: BackgammonEngine.MoveAnalysis? = nil

    // AI personality
    @Published private(set) var aiSkill: Double
    @Published var isAdaptiveAI: Bool

    // Input mode
    @Published var inputMode: InputMode {
        didSet { UserDefaults.standard.set(inputMode.rawValue, forKey: "bg.inputMode") }
    }

    private var playerRating: Double {
        didSet { UserDefaults.standard.set(playerRating, forKey: "bg.playerRating") }
    }
    private var fixedAISkill: Double {
        didSet { UserDefaults.standard.set(fixedAISkill, forKey: "bg.fixedAISkill") }
    }
    private var adaptiveTurnsAnalyzed: Int = 0

    // Coaching context (snapshot at roll time)
    private var turnStartBoard = BackgammonBoard.initial
    private var turnDice: [Int] = []

    // MARK: Init

    init() {
        let savedRating = UserDefaults.standard.double(forKey: "bg.playerRating")
        playerRating = savedRating > 0 ? savedRating : 0.35
        let savedSkill = UserDefaults.standard.double(forKey: "bg.fixedAISkill")
        fixedAISkill = savedSkill > 0 ? savedSkill : 0.55
        isAdaptiveAI = UserDefaults.standard.bool(forKey: "bg.adaptiveAI")
        let modeRaw = UserDefaults.standard.string(forKey: "bg.inputMode") ?? ""
        inputMode = InputMode(rawValue: modeRaw) ?? .checkerFirst
        if isAdaptiveAI {
            aiSkill = GameState.targetAISkill(for: savedRating > 0 ? savedRating : 0.35)
        } else {
            aiSkill = fixedAISkill > 0 ? fixedAISkill : 0.55
        }
    }

    // MARK: Rolling

    func rollDice() {
        guard phase == .rolling && currentPlayer == .white else { return }
        coachingAnalysis = nil
        turnStartBoard = board
        let d1 = Int.random(in: 1...6), d2 = Int.random(in: 1...6)
        dice = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
        usedDice = Array(repeating: false, count: dice.count)
        pendingBoard = board
        pendingMoves = []
        turnDice = dice
        clearSelection()

        let moves = BackgammonEngine.generateMoves(board: board, dice: dice, isWhite: true)
        let hasAny = moves.contains(where: { !$0.moves.isEmpty })
        if !hasAny {
            message = "No legal moves!"
            advanceTurn()
        } else {
            phase = .moving
            setMovingPrompt()
        }
    }

    // MARK: Checker-first input

    func selectPoint(_ index: Int) {
        guard phase == .moving, inputMode == .checkerFirst else { return }

        // Tapping a valid destination while a source is selected
        if let src = selectedPoint, validDestinations.contains(index) {
            if let dieIdx = dieIndexForMove(from: src, to: index, board: pendingBoard) {
                executeMove(CheckerMove(from: src, to: index), dieIndex: dieIdx)
            }
            return
        }

        // Select a new source
        let b = pendingBoard
        let hasWhiteChecker: Bool
        if index == 24 {
            hasWhiteChecker = b.whiteBar > 0
        } else {
            hasWhiteChecker = index < 24 && b.points[index] > 0
        }

        if hasWhiteChecker {
            selectedPoint = index
            validDestinations = computeDestinations(from: index, board: b,
                                                    diceValues: remainingDiceValues())
            message = validDestinations.isEmpty ? "No legal moves from here" : "Tap a highlighted point"
        } else {
            clearSelection()
            setMovingPrompt()
        }
    }

    // MARK: Dice-first input

    func selectDie(_ dieIndex: Int) {
        guard phase == .moving, inputMode == .diceFirst else { return }
        guard dieIndex < usedDice.count, !usedDice[dieIndex] else { return }

        if selectedDieIndex == dieIndex {
            selectedDieIndex = nil
            validDestinations = []
            setMovingPrompt()
        } else {
            selectedDieIndex = dieIndex
            validDestinations = computeDestsForDie(die: dice[dieIndex], board: pendingBoard)
            message = validDestinations.isEmpty ? "No moves with this die" : "Tap a point to move there"
        }
    }

    func selectDestinationWithDie(_ destIndex: Int) {
        guard phase == .moving, inputMode == .diceFirst else { return }

        if let dieIdx = selectedDieIndex {
            // Use the selected die
            guard validDestinations.contains(destIndex) else { return }
            if let src = BackgammonEngine.findSourceForDest(board: pendingBoard, dest: destIndex,
                                                            die: dice[dieIdx], isWhite: true) {
                executeMove(CheckerMove(from: src, to: destIndex), dieIndex: dieIdx)
                selectedDieIndex = nil
                validDestinations = []
            }
        } else {
            // Auto-select: try each remaining die
            let remaining = remainingDiceIndexed()
            for (dieIdx, die) in remaining {
                if let src = BackgammonEngine.findSourceForDest(board: pendingBoard, dest: destIndex,
                                                                die: die, isWhite: true) {
                    executeMove(CheckerMove(from: src, to: destIndex), dieIndex: dieIdx)
                    return
                }
            }
        }
    }

    // MARK: Unified tap dispatch

    func tapPoint(_ index: Int) {
        guard phase == .moving else { return }
        if inputMode == .checkerFirst {
            selectPoint(index)
        } else {
            selectDestinationWithDie(index)
        }
    }

    // MARK: Execute a single checker move (internal)

    private func executeMove(_ move: CheckerMove, dieIndex: Int) {
        pendingBoard = BackgammonEngine.applyMove(move, to: pendingBoard, isWhite: true)
        pendingMoves.append((move, dieIndex))
        usedDice[dieIndex] = true

        clearSelection()

        checkGameOver(board: pendingBoard)
        if phase == .gameOver { return }

        let rem = remainingDiceValues()
        if rem.isEmpty {
            message = "Tap Done to confirm your move"
        } else {
            let moreLegal = BackgammonEngine.generateMoves(board: pendingBoard, dice: rem, isWhite: true)
                .contains(where: { !$0.moves.isEmpty })
            if moreLegal {
                setMovingPrompt()
            } else {
                message = "No more legal moves — tap Done"
            }
        }
    }

    // MARK: Done / Undo

    func commitMoves() {
        guard phase == .moving else { return }
        board = pendingBoard
        pendingMoves = []
        advanceTurn()
    }

    func undoLastMove() {
        guard phase == .moving, !pendingMoves.isEmpty else { return }

        // Pop the last move
        let (_, dieIndex) = pendingMoves.removeLast()
        usedDice[dieIndex] = false

        // Rebuild pending board from committed board + remaining pending moves
        var rebuilt = board
        for (mv, _) in pendingMoves {
            rebuilt = BackgammonEngine.applyMove(mv, to: rebuilt, isWhite: true)
        }
        pendingBoard = rebuilt

        clearSelection()
        setMovingPrompt()
    }

    // MARK: AI Turn

    func triggerAITurn() {
        guard phase == .aiTurn else { return }
        let capturedSkill = aiSkill
        let capturedBoard = board
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let d1 = Int.random(in: 1...6), d2 = Int.random(in: 1...6)
            let aiDice = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
            let seq = await Task.detached(priority: .userInitiated) {
                BackgammonEngine.chooseBestMove(board: capturedBoard, dice: aiDice,
                                               isWhite: false, skill: capturedSkill)
            }.value
            let finalBoard = BackgammonEngine.applySequence(seq, to: capturedBoard, isWhite: false)
            self.board = finalBoard
            self.pendingBoard = finalBoard
            self.checkGameOver(board: finalBoard)
            if self.phase != .gameOver {
                self.currentPlayer = .white
                self.phase = .rolling
                self.message = "Your turn — roll the dice!"
            }
        }
    }

    // MARK: Advance turn (after white commits)

    private func advanceTurn() {
        // Kick off coaching analysis in background
        if currentPlayer == .white {
            let startBoard = turnStartBoard
            let endBoard   = board
            let usedArr    = turnDice
            Task {
                let analysis = await Task.detached(priority: .userInitiated) {
                    BackgammonEngine.analyzePlayerTurn(boardBefore: startBoard,
                                                       boardAfter: endBoard,
                                                       dice: usedArr, isWhite: true)
                }.value
                self.coachingAnalysis = analysis
                self.applyAdaptiveUpdate(from: analysis)
            }
        }

        currentPlayer = currentPlayer == .white ? .black : .white
        dice = []
        usedDice = []
        clearSelection()
        pendingMoves = []

        if currentPlayer == .black {
            phase = .aiTurn
            message = "AI is thinking…"
            triggerAITurn()
        } else {
            phase = .rolling
            message = "Your turn — roll the dice!"
        }
    }

    // MARK: Game over

    private func checkGameOver(board: BackgammonBoard) {
        if board.whiteOff == 15 {
            let gammon = board.blackOff == 0
            let bg = gammon && (board.blackBar > 0 || (0..<6).contains(where: { board.points[$0] < 0 }))
            gameResult = .win(isGammon: gammon, isBackgammon: bg)
            phase = .gameOver
            message = bg ? "Backgammon! You win!" : gammon ? "Gammon! You win!" : "You win!"
        } else if board.blackOff == 15 {
            let gammon = board.whiteOff == 0
            let bg = gammon && (board.whiteBar > 0 || (18..<24).contains(where: { board.points[$0] > 0 }))
            gameResult = .loss(isGammon: gammon, isBackgammon: bg)
            phase = .gameOver
            message = bg ? "Backgammon! AI wins!" : gammon ? "Gammon! AI wins!" : "AI wins!"
        }
    }

    // MARK: New game

    func newGame() {
        board = BackgammonBoard.initial
        pendingBoard = BackgammonBoard.initial
        pendingMoves = []
        currentPlayer = .white
        phase = .rolling
        dice = []
        usedDice = []
        clearSelection()
        message = "Roll to start!"
        gameResult = nil
        coachingAnalysis = nil
        adaptiveTurnsAnalyzed = 0
        aiSkill = isAdaptiveAI ? GameState.targetAISkill(for: playerRating) : fixedAISkill
    }

    // MARK: Difficulty settings

    func setFixedDifficulty(_ skill: Double) {
        fixedAISkill = skill
        isAdaptiveAI = false
        aiSkill = skill
        UserDefaults.standard.set(false, forKey: "bg.adaptiveAI")
    }

    func enableAdaptiveAI() {
        isAdaptiveAI = true
        UserDefaults.standard.set(true, forKey: "bg.adaptiveAI")
        aiSkill = GameState.targetAISkill(for: playerRating)
    }

    // MARK: Adaptive update

    private func applyAdaptiveUpdate(from analysis: BackgammonEngine.MoveAnalysis) {
        guard isAdaptiveAI else { return }
        adaptiveTurnsAnalyzed += 1
        let alpha = max(0.05, 0.30 / (1.0 + Double(adaptiveTurnsAnalyzed) * 0.04))
        playerRating = (1 - alpha) * playerRating + alpha * analysis.quality.performanceScore
        playerRating = max(0, min(1, playerRating))
        let target = GameState.targetAISkill(for: playerRating)
        aiSkill = 0.80 * aiSkill + 0.20 * target
    }

    static func targetAISkill(for playerRating: Double) -> Double {
        min(1.0, max(0.15, playerRating + 0.15))
    }

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

    var aiSkillLabel: String       { GameState.skillLabel(for: aiSkill) }
    var playerRatingLabel: String  { GameState.skillLabel(for: playerRating) }
    var playerRatingValue: Double  { playerRating }
    var adaptiveTurnsCount: Int    { adaptiveTurnsAnalyzed }

    // MARK: Commit gating

    var canCommit: Bool {
        guard phase == .moving else { return false }
        let rem = remainingDiceValues()
        if rem.isEmpty { return true }
        // Allow commit only if no legal moves remain with the remaining dice
        let moreLegal = BackgammonEngine.generateMoves(board: pendingBoard, dice: rem, isWhite: true)
            .contains(where: { !$0.moves.isEmpty })
        return !moreLegal
    }

    var canUndo: Bool {
        phase == .moving && !pendingMoves.isEmpty
    }

    // MARK: Private helpers

    func remainingDiceValues() -> [Int] {
        (0..<dice.count).filter { !usedDice[$0] }.map { dice[$0] }
    }

    private func remainingDiceIndexed() -> [(Int, Int)] {
        (0..<dice.count).filter { !usedDice[$0] }.map { ($0, dice[$0]) }
    }

    private func computeDestinations(from point: Int, board: BackgammonBoard,
                                     diceValues: [Int]) -> Set<Int> {
        var dests = Set<Int>()
        for die in Set(diceValues) {
            let singles = BackgammonEngine.legalSingleMoves(board: board, die: die, isWhite: true)
            for mv in singles where mv.from == point { dests.insert(mv.to) }
        }
        return dests
    }

    private func computeDestsForDie(die: Int, board: BackgammonBoard) -> Set<Int> {
        Set(BackgammonEngine.legalSingleMoves(board: board, die: die, isWhite: true).map { $0.to })
    }

    private func dieIndexForMove(from: Int, to: Int, board: BackgammonBoard) -> Int? {
        for (i, die) in dice.enumerated() where !usedDice[i] {
            let singles = BackgammonEngine.legalSingleMoves(board: board, die: die, isWhite: true)
            if singles.contains(where: { $0.from == from && $0.to == to }) { return i }
        }
        return nil
    }

    private func clearSelection() {
        selectedPoint    = nil
        selectedDieIndex = nil
        validDestinations = []
    }

    private func setMovingPrompt() {
        message = inputMode == .diceFirst
            ? "Select a die, then tap a point"
            : "Select a checker to move"
    }
}

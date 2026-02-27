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

@MainActor
final class GameState: ObservableObject {

    // MARK: Published state

    @Published var board = BackgammonBoard.initial
    @Published var currentPlayer: Player = .white   // White always goes first for simplicity
    @Published var phase: GamePhase = .rolling
    @Published var dice: [Int] = []
    @Published var usedDice: [Bool] = []            // Tracks which dice slots are consumed
    @Published var selectedPoint: Int? = nil        // Nil, 0-23, or 24 (bar)
    @Published var validDestinations: Set<Int> = [] // 0-23 or 24 (bear-off)
    @Published var message: String = "White's turn — tap Roll"
    @Published var gameResult: GameResult? = nil

    // MARK: - Player Actions

    func rollDice() {
        guard case .rolling = phase else { return }
        let rolled = BackgammonEngine.rollDice()
        dice = rolled
        usedDice = Array(repeating: false, count: rolled.count)

        let moves = BackgammonEngine.generateMoves(
            board: board, dice: remainingDice, isWhite: currentPlayer == .white)

        if moves.count == 1, moves[0].moves.isEmpty {
            // No legal moves — forfeit turn
            message = "\(currentPlayer.rawValue) rolled \(diceString()) — no moves available!"
            advanceTurn()
        } else {
            phase = .moving
            message = "\(currentPlayer.rawValue) rolled \(diceString()) — select a checker"
        }
    }

    func selectPoint(_ index: Int) {
        guard case .moving = phase else { return }
        let isWhite = currentPlayer == .white

        // If tapping a valid destination, make the move
        if let from = selectedPoint, validDestinations.contains(index) {
            executeMove(CheckerMove(from: from, to: index))
            return
        }

        // Select a checker owned by the current player
        let hasChecker: Bool
        if index == 24 {
            hasChecker = isWhite ? board.whiteBar > 0 : board.blackBar > 0
        } else {
            hasChecker = isWhite ? board.points[index] > 0 : board.points[index] < 0
        }

        guard hasChecker else {
            selectedPoint = nil
            validDestinations = []
            return
        }

        // Compute valid destinations for this checker using remaining dice
        selectedPoint = index
        validDestinations = computeDestinations(from: index)
    }

    func executeMove(_ move: CheckerMove) {
        guard case .moving = phase else { return }
        let isWhite = currentPlayer == .white

        // Verify this is a legal move with one of the remaining dice
        guard let dieIdx = findDie(for: move, isWhite: isWhite) else { return }

        board = BackgammonEngine.applyMove(move, to: board, isWhite: isWhite)
        usedDice[dieIdx] = true
        selectedPoint = nil
        validDestinations = []

        // Check win condition
        if let result = BackgammonEngine.gameResult(board) {
            gameResult = result
            phase = .gameOver(result)
            message = result.description
            return
        }

        // Check if all dice are used or no more moves possible
        let rem = remainingDice
        if rem.isEmpty {
            advanceTurn()
            return
        }

        let moreMoves = BackgammonEngine.generateMoves(board: board, dice: rem, isWhite: isWhite)
        if moreMoves.count == 1, moreMoves[0].moves.isEmpty {
            message = "No more moves — switching turn"
            advanceTurn()
        } else {
            message = "\(currentPlayer.rawValue) — select a checker (\(rem.count) die\(rem.count == 1 ? "" : "s") left)"
        }
    }

    // MARK: - AI Turn

    func triggerAITurn() {
        guard currentPlayer == .black else { return }
        phase = .aiTurn
        message = "Black is thinking…"

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s UX pause before showing roll

            let rolled = BackgammonEngine.rollDice()
            self.dice = rolled
            self.usedDice = Array(repeating: false, count: rolled.count)
            self.message = "Black rolled \(self.diceString()) — computing best move…"

            // Snapshot board so the background task captures a value type, not self.
            let boardSnapshot = self.board

            // Run the 2-ply expectimax search on a background thread so the main
            // actor (and therefore the UI) stays fully responsive during computation.
            let best = await Task.detached(priority: .userInitiated) {
                BackgammonEngine.chooseBestMove(board: boardSnapshot, dice: rolled, isWhite: false)
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
        currentPlayer = currentPlayer == .white ? .black : .white
        dice = []
        usedDice = []
        selectedPoint = nil
        validDestinations = []

        if currentPlayer == .black {
            phase = .aiTurn
            triggerAITurn()
        } else {
            phase = .rolling
            message = "White's turn — tap Roll"
        }
    }

    private var remainingDice: [Int] {
        zip(dice, usedDice).compactMap { (die, used) in used ? nil : die }
    }

    private func findDie(for move: CheckerMove, isWhite: Bool) -> Int? {
        // Determine which die value this move uses
        let dieValue: Int
        if move.from == 24 {
            // Bar entry
            dieValue = isWhite ? (24 - move.to) : (move.to + 1)
        } else if move.to == 24 {
            // Bear-off (may be exact or over-bear — find smallest valid remaining die)
            let distance = isWhite ? (move.from + 1) : (24 - move.from)
            // Find smallest die >= distance, or if all are >, pick smallest
            let rem = zip(dice, usedDice).enumerated().filter { !$0.element.1 }.map { ($0.offset, $0.element.0) }
            if let exact = rem.first(where: { $0.1 == distance }) { return exact.0 }
            if let over = rem.filter({ $0.1 > distance }).min(by: { $0.1 < $1.1 }) { return over.0 }
            return nil
        } else {
            dieValue = abs(move.to - move.from)
        }
        return zip(dice, usedDice).enumerated().first(where: { !$0.element.1 && $0.element.0 == dieValue })?.offset
    }

    private func computeDestinations(from source: Int) -> Set<Int> {
        let isWhite = currentPlayer == .white
        var dests = Set<Int>()
        var tried = Set<Int>()

        for die in remainingDice {
            guard !tried.contains(die) else { continue }
            tried.insert(die)
            let singles = BackgammonEngine.legalSingleMoves(board: board, die: die, isWhite: isWhite)
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
        currentPlayer = .white
        phase = .rolling
        dice = []
        usedDice = []
        selectedPoint = nil
        validDestinations = []
        gameResult = nil
        message = "White's turn — tap Roll"
    }
}

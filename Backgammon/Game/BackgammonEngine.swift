// BackgammonEngine.swift
// Core backgammon game logic inspired by GNU Backgammon (GNUbg) conventions.
//
// Board coordinate system (absolute, matching GNUbg display conventions):
//   points[0]  = point  1  (White's 1-point / ace-point, bottom-right)
//   points[23] = point 24  (Black's 1-point / ace-point, top-right)
//   Positive value → White checkers; Negative value → Black checkers.
//
//   White moves:  index 23 → index 0 (high to low), bears off past index -1.
//   Black moves:  index  0 → index 23 (low to high), bears off past index 24.

import Foundation

// MARK: - Core Types

struct BackgammonBoard: Equatable {
    /// 24 points. Positive = White checkers, Negative = Black checkers.
    var points: [Int] = Array(repeating: 0, count: 24)
    var whiteBar: Int = 0
    var blackBar: Int = 0
    var whiteOff: Int = 0
    var blackOff: Int = 0

    // MARK: Standard starting position
    static let initial: BackgammonBoard = {
        var b = BackgammonBoard()
        b.points[0]  = -2   // 2 Black  on point  1
        b.points[5]  =  5   // 5 White  on point  6
        b.points[7]  =  3   // 3 White  on point  8
        b.points[11] = -5   // 5 Black  on point 12
        b.points[12] =  5   // 5 White  on point 13
        b.points[16] = -3   // 3 Black  on point 17
        b.points[18] = -5   // 5 Black  on point 19
        b.points[23] =  2   // 2 White  on point 24
        return b
    }()

    // MARK: Bear-off eligibility
    /// White can bear off when all remaining White checkers are on points 1-6 (indices 0-5).
    var whiteCanBearOff: Bool {
        guard whiteBar == 0 else { return false }
        for i in 6..<24 where points[i] > 0 { return false }
        return true
    }

    /// Black can bear off when all remaining Black checkers are on points 19-24 (indices 18-23).
    var blackCanBearOff: Bool {
        guard blackBar == 0 else { return false }
        for i in 0..<18 where points[i] < 0 { return false }
        return true
    }
}

/// A single checker movement.
/// `from` / `to`: 0-23 = point index; 24 = bar (source) or bear-off (destination).
struct CheckerMove: Hashable {
    let from: Int
    let to: Int
}

/// A complete move sequence using one full set of dice.
struct MoveSequence: Hashable {
    let moves: [CheckerMove]
}

enum Player: String {
    case white = "White"
    case black = "Black"
}

enum GameResult {
    case normal(winner: Player)
    case gammon(winner: Player)
    case backgammon(winner: Player)

    var winner: Player {
        switch self {
        case .normal(let w), .gammon(let w), .backgammon(let w): return w
        }
    }

    var description: String {
        switch self {
        case .normal(let w):     return "\(w.rawValue) wins!"
        case .gammon(let w):     return "\(w.rawValue) wins a Gammon!"
        case .backgammon(let w): return "\(w.rawValue) wins a Backgammon!"
        }
    }
}

// MARK: - GNU Backgammon–inspired Engine

enum BackgammonEngine {

    // MARK: Dice

    static func rollDice() -> [Int] {
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)
        return d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
    }

    // MARK: Move Application

    static func applyMove(_ move: CheckerMove, to board: BackgammonBoard, isWhite: Bool) -> BackgammonBoard {
        var b = board

        // Remove checker from source
        if move.from == 24 {
            if isWhite { b.whiteBar -= 1 } else { b.blackBar -= 1 }
        } else {
            if isWhite { b.points[move.from] -= 1 } else { b.points[move.from] += 1 }
        }

        // Place checker at destination
        if move.to == 24 {
            if isWhite { b.whiteOff += 1 } else { b.blackOff += 1 }
        } else {
            if isWhite {
                // Hit a Black blot?
                if b.points[move.to] == -1 { b.points[move.to] = 0; b.blackBar += 1 }
                b.points[move.to] += 1
            } else {
                // Hit a White blot?
                if b.points[move.to] == 1 { b.points[move.to] = 0; b.whiteBar += 1 }
                b.points[move.to] -= 1
            }
        }

        return b
    }

    // MARK: Legal Single-Die Moves

    /// Returns every legal checker move for one die value.
    static func legalSingleMoves(board: BackgammonBoard, die: Int, isWhite: Bool) -> [CheckerMove] {
        var moves: [CheckerMove] = []

        if isWhite {
            // --- White ---
            // Must enter from bar first.
            if board.whiteBar > 0 {
                // White enters Black's home board (points 19-24, indices 18-23).
                // With die d, entry point = (25 - d) → index = (24 - d).
                let idx = 24 - die
                if (0..<24).contains(idx), board.points[idx] >= -1 {
                    moves.append(CheckerMove(from: 24, to: idx))
                }
                return moves
            }

            for i in 0..<24 {
                guard board.points[i] > 0 else { continue }
                let dest = i - die
                if dest >= 0 {
                    // Normal move
                    if board.points[dest] >= -1 { moves.append(CheckerMove(from: i, to: dest)) }
                } else if board.whiteCanBearOff {
                    // Bear-off (dest < 0 means the checker moves off the board).
                    // dest == -1  → exact bear-off (die == i+1).
                    // dest <  -1  → over-bear; only legal from the highest occupied home-board point.
                    if dest == -1 {
                        moves.append(CheckerMove(from: i, to: 24))
                    } else {
                        // Over-bear: no checker on any higher home-board point.
                        let hasHigher = (i+1..<6).contains { board.points[$0] > 0 }
                        if !hasHigher { moves.append(CheckerMove(from: i, to: 24)) }
                    }
                }
            }

        } else {
            // --- Black ---
            // Must enter from bar first.
            if board.blackBar > 0 {
                // Black enters White's home board (points 1-6, indices 0-5).
                // With die d, entry point = d → index = d-1.
                let idx = die - 1
                if (0..<24).contains(idx), board.points[idx] <= 1 {
                    moves.append(CheckerMove(from: 24, to: idx))
                }
                return moves
            }

            for i in 0..<24 {
                guard board.points[i] < 0 else { continue }
                let dest = i + die
                if dest < 24 {
                    // Normal move
                    if board.points[dest] <= 1 { moves.append(CheckerMove(from: i, to: dest)) }
                } else if board.blackCanBearOff {
                    // Bear-off. dest == 24 → exact; dest > 24 → over-bear.
                    if dest == 24 {
                        moves.append(CheckerMove(from: i, to: 24))
                    } else {
                        // Over-bear: no checker on any higher home-board index.
                        let hasHigher = (i+1..<24).contains { board.points[$0] < 0 }
                        if !hasHigher { moves.append(CheckerMove(from: i, to: 24)) }
                    }
                }
            }
        }

        return moves
    }

    // MARK: Full Move Generation (GNUbg: must use maximum number of dice)

    static func generateMoves(board: BackgammonBoard, dice: [Int], isWhite: Bool) -> [MoveSequence] {
        var allSeqs: [(moves: [CheckerMove], final: BackgammonBoard)] = []
        var maxUsed = 0

        func recurse(_ b: BackgammonBoard, _ remaining: [Int], _ current: [CheckerMove]) {
            var moved = false
            var tried = Set<Int>()

            for (i, die) in remaining.enumerated() {
                guard !tried.contains(die) else { continue }
                tried.insert(die)

                var next = remaining
                next.remove(at: i)

                let singles = legalSingleMoves(board: b, die: die, isWhite: isWhite)
                for m in singles {
                    moved = true
                    recurse(applyMove(m, to: b, isWhite: isWhite), next, current + [m])
                }
            }

            if !moved {
                let count = current.count
                if count > maxUsed { maxUsed = count; allSeqs.removeAll() }
                if count == maxUsed { allSeqs.append((current, b)) }
            }
        }

        recurse(board, dice, [])

        // Deduplicate by resulting board state
        var seen = Set<String>()
        var unique: [MoveSequence] = []
        for s in allSeqs {
            let key = boardKey(s.final)
            if seen.insert(key).inserted {
                unique.append(MoveSequence(moves: s.moves))
            }
        }
        return unique.isEmpty ? [MoveSequence(moves: [])] : unique
    }

    // MARK: Position Evaluation (GNUbg-style heuristic)

    /// Returns a score from White's perspective (higher = better for White).
    static func evaluate(_ board: BackgammonBoard) -> Double {
        if board.whiteOff == 15 { return  1000 }
        if board.blackOff == 15 { return -1000 }

        var score: Double = 0

        // 1. Pip count differential
        score += Double(blackPip(board) - whitePip(board)) * 0.05

        // 2. Blot danger
        for i in 0..<24 {
            if board.points[i] == 1 {
                score -= 0.15 + Double(directShots(board, point: i, byBlack: true)) * 0.25
            } else if board.points[i] == -1 {
                score += 0.15 + Double(directShots(board, point: i, byBlack: false)) * 0.25
            }
        }

        // 3. Primes
        score += Double(longestPrime(board, isWhite: true))  * 0.20
        score -= Double(longestPrime(board, isWhite: false)) * 0.20

        // 4. Home board coverage
        let wHome = (0..<6).filter  { board.points[$0] >= 2 }.count
        let bHome = (18..<24).filter { board.points[$0] <= -2 }.count
        score += Double(wHome) * 0.10
        score -= Double(bHome) * 0.10

        // 5. Bar penalty
        score -= Double(board.whiteBar) * 2.0
        score += Double(board.blackBar) * 2.0

        // 6. Anchor in opponent home board
        let wAnchors = (18..<24).filter { board.points[$0] >= 2 }.count
        let bAnchors = (0..<6).filter   { board.points[$0] <= -2 }.count
        score += Double(wAnchors) * 0.30
        score -= Double(bAnchors) * 0.30

        return score
    }

    // MARK: AI Move Selection

    static func chooseBestMove(board: BackgammonBoard, dice: [Int], isWhite: Bool) -> MoveSequence {
        let seqs = generateMoves(board: board, dice: dice, isWhite: isWhite)
        guard seqs.count > 1 else { return seqs[0] }

        var bestScore = isWhite ? -Double.infinity : Double.infinity
        var best = seqs[0]

        for seq in seqs {
            var b = board
            for m in seq.moves { b = applyMove(m, to: b, isWhite: isWhite) }
            let s = evaluate(b)
            if isWhite ? (s > bestScore) : (s < bestScore) {
                bestScore = s
                best = seq
            }
        }
        return best
    }

    // MARK: Game-Over Detection

    static func gameResult(_ board: BackgammonBoard) -> GameResult? {
        if board.whiteOff == 15 {
            if board.blackOff == 0 {
                let hasBlackInWhiteHome = (0..<6).contains { board.points[$0] < 0 }
                return (board.blackBar > 0 || hasBlackInWhiteHome)
                    ? .backgammon(winner: .white) : .gammon(winner: .white)
            }
            return .normal(winner: .white)
        }
        if board.blackOff == 15 {
            if board.whiteOff == 0 {
                let hasWhiteInBlackHome = (18..<24).contains { board.points[$0] > 0 }
                return (board.whiteBar > 0 || hasWhiteInBlackHome)
                    ? .backgammon(winner: .black) : .gammon(winner: .black)
            }
            return .normal(winner: .black)
        }
        return nil
    }

    // MARK: Helpers

    private static func whitePip(_ b: BackgammonBoard) -> Int {
        var pip = b.whiteBar * 25
        for i in 0..<24 where b.points[i] > 0 { pip += b.points[i] * (i + 1) }
        return pip
    }

    private static func blackPip(_ b: BackgammonBoard) -> Int {
        var pip = b.blackBar * 25
        for i in 0..<24 where b.points[i] < 0 { pip += (-b.points[i]) * (24 - i) }
        return pip
    }

    /// Number of Black (or White) checkers that can hit the blot at `point` in one roll.
    private static func directShots(_ b: BackgammonBoard, point: Int, byBlack: Bool) -> Int {
        var count = 0
        for die in 1...6 {
            let src = byBlack ? point - die : point + die
            if (0..<24).contains(src) {
                let checker = b.points[src]
                if byBlack ? (checker < 0) : (checker > 0) { count += 1 }
            }
            // Bar
            if byBlack, src == -1, b.blackBar > 0 { count += 1 }
            if !byBlack, src == 24, b.whiteBar > 0 { count += 1 }
        }
        return min(count, 6)
    }

    private static func longestPrime(_ b: BackgammonBoard, isWhite: Bool) -> Int {
        var max = 0, cur = 0
        for i in 0..<24 {
            if isWhite ? (b.points[i] >= 2) : (b.points[i] <= -2) {
                cur += 1
                if cur > max { max = cur }
            } else {
                cur = 0
            }
        }
        return max
    }

    private static func boardKey(_ b: BackgammonBoard) -> String {
        b.points.map(String.init).joined(separator: ",")
        + "|\(b.whiteBar),\(b.blackBar),\(b.whiteOff),\(b.blackOff)"
    }
}

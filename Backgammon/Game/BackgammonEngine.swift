// BackgammonEngine.swift
// Core backgammon game logic inspired by GNU Backgammon (GNUbg) conventions.
//
// Board coordinate system (absolute):
//   points[0]  = point  1  (White's ace-point, bottom-right)
//   points[23] = point 24  (Black's ace-point, top-right)
//   Positive → White checkers; Negative → Black checkers.
//   White moves high→low (index 23 → 0), bears off past index -1.
//   Black moves low→high (index 0 → 23), bears off past index 24.
//
// AI strength improvements over a simple 1-ply greedy search:
//   • 2-ply expectimax — for each candidate move, averages the opponent's
//     best 1-ply response across all 21 possible dice rolls.
//   • Race/contact split — uses a dedicated race formula when the position is
//     a pure pip race (no checker can block or hit an opponent).
//   • Point-value weighting — 5-point and bar-point score higher than generic
//     blocking points; deep anchors in the opponent's home board are rewarded.
//   • Location-aware blot danger — blots in the opponent's home board carry
//     a larger penalty than blots safely inside one's own home board.
//   • Stacking wastage — excessive checkers piled on one point in a race are
//     penalised (they waste pip potential).

import Foundation

// MARK: - Core Types

struct BackgammonBoard: Equatable {
    var points: [Int] = Array(repeating: 0, count: 24)
    var whiteBar: Int = 0
    var blackBar: Int = 0
    var whiteOff: Int = 0
    var blackOff: Int = 0

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

    var whiteCanBearOff: Bool {
        guard whiteBar == 0 else { return false }
        for i in 6..<24 where points[i] > 0 { return false }
        return true
    }

    var blackCanBearOff: Bool {
        guard blackBar == 0 else { return false }
        for i in 0..<18 where points[i] < 0 { return false }
        return true
    }
}

struct CheckerMove: Hashable {
    let from: Int   // 0-23 = point index; 24 = bar
    let to: Int     // 0-23 = point index; 24 = bear-off
}

struct MoveSequence: Hashable {
    let moves: [CheckerMove]
}

enum Player: String { case white = "White"; case black = "Black" }

enum GameResult {
    case normal(winner: Player)
    case gammon(winner: Player)
    case backgammon(winner: Player)

    var winner: Player {
        switch self { case .normal(let w), .gammon(let w), .backgammon(let w): return w }
    }
    var description: String {
        switch self {
        case .normal(let w):     return "\(w.rawValue) wins!"
        case .gammon(let w):     return "\(w.rawValue) wins a Gammon!"
        case .backgammon(let w): return "\(w.rawValue) wins a Backgammon!"
        }
    }
}

// MARK: - Engine

enum BackgammonEngine {

    // MARK: Dice

    static func rollDice() -> [Int] {
        let d1 = Int.random(in: 1...6), d2 = Int.random(in: 1...6)
        return d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
    }

    // MARK: Move Application

    static func applyMove(_ move: CheckerMove, to board: BackgammonBoard, isWhite: Bool) -> BackgammonBoard {
        var b = board
        if move.from == 24 { if isWhite { b.whiteBar -= 1 } else { b.blackBar -= 1 } }
        else               { if isWhite { b.points[move.from] -= 1 } else { b.points[move.from] += 1 } }

        if move.to == 24 { if isWhite { b.whiteOff += 1 } else { b.blackOff += 1 } }
        else {
            if isWhite {
                if b.points[move.to] == -1 { b.points[move.to] = 0; b.blackBar += 1 }
                b.points[move.to] += 1
            } else {
                if b.points[move.to] ==  1 { b.points[move.to] = 0; b.whiteBar += 1 }
                b.points[move.to] -= 1
            }
        }
        return b
    }

    // MARK: Legal Single-Die Moves

    static func legalSingleMoves(board: BackgammonBoard, die: Int, isWhite: Bool) -> [CheckerMove] {
        var moves: [CheckerMove] = []

        if isWhite {
            if board.whiteBar > 0 {
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
                    if board.points[dest] >= -1 { moves.append(CheckerMove(from: i, to: dest)) }
                } else if board.whiteCanBearOff {
                    if dest == -1 {
                        moves.append(CheckerMove(from: i, to: 24))
                    } else {
                        let hasHigher = (i+1..<6).contains { board.points[$0] > 0 }
                        if !hasHigher { moves.append(CheckerMove(from: i, to: 24)) }
                    }
                }
            }
        } else {
            if board.blackBar > 0 {
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
                    if board.points[dest] <= 1 { moves.append(CheckerMove(from: i, to: dest)) }
                } else if board.blackCanBearOff {
                    if dest == 24 {
                        moves.append(CheckerMove(from: i, to: 24))
                    } else {
                        let hasHigher = (i+1..<24).contains { board.points[$0] < 0 }
                        if !hasHigher { moves.append(CheckerMove(from: i, to: 24)) }
                    }
                }
            }
        }
        return moves
    }

    // MARK: Full Move Generation

    static func generateMoves(board: BackgammonBoard, dice: [Int], isWhite: Bool) -> [MoveSequence] {
        var allSeqs: [(moves: [CheckerMove], final: BackgammonBoard)] = []
        var maxUsed = 0

        func recurse(_ b: BackgammonBoard, _ remaining: [Int], _ current: [CheckerMove]) {
            var moved = false
            var tried = Set<Int>()
            for (i, die) in remaining.enumerated() {
                guard tried.insert(die).inserted else { continue }
                var next = remaining; next.remove(at: i)
                for m in legalSingleMoves(board: b, die: die, isWhite: isWhite) {
                    moved = true
                    recurse(applyMove(m, to: b, isWhite: isWhite), next, current + [m])
                }
            }
            if !moved {
                let n = current.count
                if n > maxUsed { maxUsed = n; allSeqs.removeAll() }
                if n == maxUsed { allSeqs.append((current, b)) }
            }
        }
        recurse(board, dice, [])

        var seen = Set<String>()
        var unique: [MoveSequence] = []
        for s in allSeqs {
            if seen.insert(boardKey(s.final)).inserted { unique.append(MoveSequence(moves: s.moves)) }
        }
        return unique.isEmpty ? [MoveSequence(moves: [])] : unique
    }

    // MARK: - Position Evaluation

    // ── Entry point ──────────────────────────────────────────────────────────

    /// Returns a score from White's perspective (higher = better for White).
    /// Dispatches to a race-specific or contact-specific model.
    static func evaluate(_ board: BackgammonBoard) -> Double {
        if board.whiteOff == 15 { return  1000 }
        if board.blackOff == 15 { return -1000 }
        return hasContact(board) ? contactEval(board) : raceEval(board)
    }

    // ── Race / contact detection ──────────────────────────────────────────────

    /// Pure race: every White checker's index is strictly less than every
    /// Black checker's index (no overlap, so no checker can block or hit).
    static func hasContact(_ board: BackgammonBoard) -> Bool {
        if board.whiteBar > 0 || board.blackBar > 0 { return true }
        var maxWhite = -1, minBlack = 24
        for i in 0..<24 {
            if board.points[i] > 0 { maxWhite = i }
            if board.points[i] < 0, minBlack == 24 { minBlack = i }
        }
        return maxWhite >= minBlack
    }

    // ── Race evaluation ───────────────────────────────────────────────────────
    //
    // In a pure race pip count is the dominant factor.  We add a small
    // "wastage" adjustment: excess checkers piled on a single point cannot all
    // be moved efficiently, effectively costing extra pips.

    private static func raceEval(_ board: BackgammonBoard) -> Double {
        let pipDiff = Double(blackPip(board) - whitePip(board))
        let waste   = wastage(board, isWhite: false) - wastage(board, isWhite: true)
        // ~8-pip lead ≈ ~70 % win probability; scale to give sensible score range.
        return (pipDiff + waste) * 0.13
    }

    /// Pips wasted due to stacking (beyond 2 checkers on a point is
    /// inefficient in a bear-off; each extra checker costs ~0.5 effective pips).
    private static func wastage(_ board: BackgammonBoard, isWhite: Bool) -> Double {
        var w = 0.0
        if isWhite {
            for i in 0..<6  { let n = board.points[i];  if n > 2 { w += Double(n - 2) * 0.5 } }
        } else {
            for i in 18..<24 { let n = -board.points[i]; if n > 2 { w += Double(n - 2) * 0.5 } }
        }
        return w
    }

    // ── Contact evaluation ────────────────────────────────────────────────────
    //
    // Combines six weighted terms:
    //   pip differential, blot danger, point values, prime length,
    //   bar penalty, and board-closure bonus.

    private static func contactEval(_ board: BackgammonBoard) -> Double {
        var score = 0.0

        // 1. Pip count (moderate weight in contact; race isn't settled yet)
        score += Double(blackPip(board) - whitePip(board)) * 0.04

        // 2. Blot exposure (weighted by number of direct shots AND location)
        for i in 0..<24 {
            switch board.points[i] {
            case 1:    // White blot
                let shots = directShots(board, at: i, byBlack: true)
                score -= (0.08 + Double(shots) * 0.16) * blotLocationFactor(i, isWhitePiece: true)
            case -1:   // Black blot
                let shots = directShots(board, at: i, byBlack: false)
                score += (0.08 + Double(shots) * 0.16) * blotLocationFactor(i, isWhitePiece: false)
            default: break
            }
        }

        // 3. Controlled points (≥2 checkers) — quality-weighted by position
        for i in 0..<24 {
            let n = board.points[i]
            if n >= 2  { score += pointValue(i, isWhite: true)  }
            if n <= -2 { score -= pointValue(i, isWhite: false) }
        }

        // 4. Prime length
        score += Double(longestPrime(board, isWhite: true))  * 0.18
        score -= Double(longestPrime(board, isWhite: false)) * 0.18

        // 5. Bar penalty
        score -= Double(board.whiteBar) * 2.5
        score += Double(board.blackBar) * 2.5

        // 6. Board-closure bonus: opponent on bar with home-board points made
        if board.blackBar > 0 {
            let pts = (0..<6).filter { board.points[$0] >= 2 }.count
            score += Double(pts) * 0.45
        }
        if board.whiteBar > 0 {
            let pts = (18..<24).filter { board.points[$0] <= -2 }.count
            score -= Double(pts) * 0.45
        }

        // 7. Bearoff progress
        score += Double(board.whiteOff) * 0.30
        score -= Double(board.blackOff) * 0.30

        return score
    }

    // ── Point-value table ─────────────────────────────────────────────────────
    //
    // Owning the 5-point or bar-point is disproportionately strong.
    // Deep anchors in the opponent's home board provide safety.

    private static func pointValue(_ index: Int, isWhite: Bool) -> Double {
        let rel = isWhite ? index : (23 - index)  // 0-23, 0 = player's 1-point
        switch rel {
        case 4:     return 0.50   // Golden 5-point
        case 6:     return 0.38   // Bar-point
        case 18...23: return 0.32 // Deep anchor in opponent's home board
        case 0...5: return 0.22   // Regular home-board point
        default:    return 0.15   // Outer-board point
        }
    }

    // ── Location-aware blot danger ────────────────────────────────────────────
    //
    // A blot deep in the opponent's home board (far from re-entry) is more
    // costly than a blot in one's own home board.

    private static func blotLocationFactor(_ index: Int, isWhitePiece: Bool) -> Double {
        let rel = isWhitePiece ? (23 - index) : index  // distance from player's bear-off end
        switch rel {
        case 0...5:   return 0.70   // Own home board — less dangerous
        case 6...11:  return 1.00   // Outer board — average
        case 12...17: return 1.20   // Opponent's outer board
        default:      return 1.55   // Deep in opponent's home board — very dangerous
        }
    }

    // MARK: - 2-Ply Expectimax Move Selection
    //
    // Algorithm:
    //   1. Generate all legal move sequences for the current dice roll.
    //   2. Score each with a 1-ply evaluation to rank candidates quickly.
    //   3. Keep the top-K candidates (avoids evaluating hopeless moves at 2-ply).
    //   4. For each candidate, compute the *expected* position score by
    //      considering every one of the 21 possible opponent dice rolls,
    //      having the opponent pick their best 1-ply response for each roll,
    //      then probability-weighting and summing those scores.
    //   5. Return the candidate with the best expected score.
    //
    // Complexity: K × 21 × (avg opponent moves) evaluations.
    // With K=16 and ~15 average opponent moves: ~5 000 evals per AI turn — fast.

    static func chooseBestMove(board: BackgammonBoard, dice: [Int], isWhite: Bool) -> MoveSequence {
        let seqs = generateMoves(board: board, dice: dice, isWhite: isWhite)
        guard seqs.count > 1 else { return seqs[0] }

        // --- 1-ply ranking ---
        var oneply: [(seq: MoveSequence, board: BackgammonBoard, score: Double)] = seqs.map { seq in
            var b = board
            for m in seq.moves { b = applyMove(m, to: b, isWhite: isWhite) }
            return (seq, b, evaluate(b))
        }
        oneply.sort { isWhite ? $0.score > $1.score : $0.score < $1.score }

        // --- 2-ply expectimax on top-K ---
        let K = min(oneply.count, 16)
        var bestScore = isWhite ? -Double.infinity : Double.infinity
        var best = oneply[0].seq

        for entry in oneply.prefix(K) {
            // If the game ends after this move, its 1-ply score is exact.
            let s: Double
            if gameResult(entry.board) != nil {
                s = entry.score
            } else {
                s = expectedOpponentScore(after: entry.board, opponentIsWhite: !isWhite)
            }
            if isWhite ? (s > bestScore) : (s < bestScore) {
                bestScore = s; best = entry.seq
            }
        }
        return best
    }

    /// Averages the opponent's best 1-ply response across all 21 dice rolls.
    /// This is the "chance node" in the expectimax tree.
    static func expectedOpponentScore(after board: BackgammonBoard, opponentIsWhite: Bool) -> Double {
        var total = 0.0
        for d1 in 1...6 {
            for d2 in d1...6 {
                let weight = d1 == d2 ? 1.0/36.0 : 2.0/36.0
                let opDice = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
                let opSeqs = generateMoves(board: board, dice: opDice, isWhite: opponentIsWhite)

                var opBest = opponentIsWhite ? -Double.infinity : Double.infinity
                for seq in opSeqs {
                    var b = board
                    for m in seq.moves { b = applyMove(m, to: b, isWhite: opponentIsWhite) }
                    let s = evaluate(b)
                    if opponentIsWhite ? (s > opBest) : (s < opBest) { opBest = s }
                }
                total += (opBest.isFinite ? opBest : evaluate(board)) * weight
            }
        }
        return total
    }

    // MARK: - Game-Over Detection

    static func gameResult(_ board: BackgammonBoard) -> GameResult? {
        if board.whiteOff == 15 {
            if board.blackOff == 0 {
                let bg = board.blackBar > 0 || (0..<6).contains(where:  { board.points[$0] < 0 })
                return bg ? .backgammon(winner: .white) : .gammon(winner: .white)
            }
            return .normal(winner: .white)
        }
        if board.blackOff == 15 {
            if board.whiteOff == 0 {
                let bg = board.whiteBar > 0 || (18..<24).contains(where: { board.points[$0] > 0 })
                return bg ? .backgammon(winner: .black) : .gammon(winner: .black)
            }
            return .normal(winner: .black)
        }
        return nil
    }

    // MARK: - Private Helpers

    static func whitePip(_ b: BackgammonBoard) -> Int {
        var p = b.whiteBar * 25
        for i in 0..<24 where b.points[i] > 0 { p += b.points[i] * (i + 1) }
        return p
    }

    static func blackPip(_ b: BackgammonBoard) -> Int {
        var p = b.blackBar * 25
        for i in 0..<24 where b.points[i] < 0 { p += (-b.points[i]) * (24 - i) }
        return p
    }

    private static func directShots(_ board: BackgammonBoard, at point: Int, byBlack: Bool) -> Int {
        var count = 0
        for die in 1...6 {
            let src = byBlack ? point - die : point + die
            if (0..<24).contains(src) {
                count += byBlack ? (board.points[src] < 0 ? 1 : 0)
                                 : (board.points[src] > 0 ? 1 : 0)
            }
            if byBlack,  src == -1, board.blackBar > 0 { count += 1 }
            if !byBlack, src == 24, board.whiteBar > 0 { count += 1 }
        }
        return min(count, 6)
    }

    private static func longestPrime(_ b: BackgammonBoard, isWhite: Bool) -> Int {
        var best = 0, cur = 0
        for i in 0..<24 {
            if isWhite ? (b.points[i] >= 2) : (b.points[i] <= -2) { cur += 1; best = max(best, cur) }
            else { cur = 0 }
        }
        return best
    }

    private static func boardKey(_ b: BackgammonBoard) -> String {
        b.points.map(String.init).joined(separator: ",")
        + "|\(b.whiteBar),\(b.blackBar),\(b.whiteOff),\(b.blackOff)"
    }
}

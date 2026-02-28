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

    // MARK: - Move Selection (variable skill)
    //
    // skill ∈ [0, 1] controls strength:
    //
    //   1.00 — Expert: deterministic 2-ply expectimax (same as before).
    //   ≥0.65 — Strong: 2-ply scores the top-K candidates, but the final
    //            choice is drawn from a softmax distribution (higher temp →
    //            more likely to pick a sub-optimal move).
    //   <0.65 — Weak:   Only 1-ply scores are used — simulates an opponent
    //            who does not look ahead at the opponent's replies.
    //   ≈0.00 — Novice: flat softmax distribution ≈ random move selection.
    //
    // analyzePlayerTurn always calls chooseBestMove without a skill argument
    // so it defaults to 1.0 and always finds the true reference best move.

    static func chooseBestMove(board: BackgammonBoard, dice: [Int], isWhite: Bool,
                               skill: Double = 1.0) -> MoveSequence {
        let seqs = generateMoves(board: board, dice: dice, isWhite: isWhite)
        guard seqs.count > 1 else { return seqs[0] }

        // 1-ply ranking of every candidate.
        let scored: [(seq: MoveSequence, board: BackgammonBoard, score: Double)] = seqs.map { seq in
            var b = board
            for m in seq.moves { b = applyMove(m, to: b, isWhite: isWhite) }
            return (seq, b, evaluate(b))
        }.sorted { isWhite ? $0.score > $1.score : $0.score < $1.score }

        let s = min(1.0, max(0.0, skill))

        // Expert path: deterministic 2-ply expectimax.
        if s >= 0.98 { return expectimaxPick(from: scored, isWhite: isWhite) }

        // Build final candidate list with 2-ply scores at higher skill,
        // 1-ply scores at lower skill (no lookahead).
        let candidates: [(seq: MoveSequence, score: Double)]
        if s >= 0.65 {
            candidates = scored.prefix(min(scored.count, 16)).map { entry in
                let score = gameResult(entry.board) != nil
                    ? entry.score
                    : expectedOpponentScore(after: entry.board, opponentIsWhite: !isWhite)
                return (entry.seq, score)
            }
        } else {
            candidates = scored.map { ($0.seq, $0.score) }
        }

        // Softmax sample — scores from the current player's perspective (higher = better).
        let myScores = candidates.map { isWhite ? $0.score : -$0.score }
        return softmaxSample(items: candidates.map { $0.seq },
                             scores: myScores,
                             temperature: temperatureForSkill(s))
    }

    // Deterministic 2-ply pick (the original expert algorithm).
    private static func expectimaxPick(
        from scored: [(seq: MoveSequence, board: BackgammonBoard, score: Double)],
        isWhite: Bool
    ) -> MoveSequence {
        let K = min(scored.count, 16)
        var bestScore = isWhite ? -Double.infinity : Double.infinity
        var best = scored[0].seq
        for entry in scored.prefix(K) {
            let s = gameResult(entry.board) != nil
                ? entry.score
                : expectedOpponentScore(after: entry.board, opponentIsWhite: !isWhite)
            if isWhite ? (s > bestScore) : (s < bestScore) { bestScore = s; best = entry.seq }
        }
        return best
    }

    /// Softmax temperature for a given skill level.
    /// skill=0 → ≈8.2 (near-random); skill=0.5 → ≈3.0; skill=0.9 → ≈0.45 (decisive).
    static func temperatureForSkill(_ skill: Double) -> Double {
        0.2 + 8.0 * pow(1.0 - skill, 1.5)
    }

    /// Draws one item from a softmax distribution over `scores`.
    private static func softmaxSample(items: [MoveSequence], scores: [Double],
                                      temperature: Double) -> MoveSequence {
        guard items.count > 1 else { return items[0] }
        let maxScore = scores.max()!
        let expScores = scores.map { exp(($0 - maxScore) / temperature) }
        let total = expScores.reduce(0.0, +)
        var r = Double.random(in: 0..<total)
        for (item, e) in zip(items, expScores) { r -= e; if r <= 0 { return item } }
        return items.last!
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

    // MARK: - Coaching Types

    /// How close the player's move was to the engine's best move.
    enum MoveQuality {
        case optimal      // Player chose the best available move
        case excellent    // Very close to optimal
        case good         // Reasonable play
        case inaccuracy   // Noticeably suboptimal
        case mistake      // Significant error
        case blunder      // Severe error

        var label: String {
            switch self {
            case .optimal:    return "Best move!"
            case .excellent:  return "Excellent"
            case .good:       return "Good move"
            case .inaccuracy: return "Slight inaccuracy"
            case .mistake:    return "Mistake"
            case .blunder:    return "Blunder"
            }
        }

        /// SwiftUI color name suitable for display.
        var colorName: String {
            switch self {
            case .optimal, .excellent: return "green"
            case .good:                return "teal"
            case .inaccuracy:          return "yellow"
            case .mistake:             return "orange"
            case .blunder:             return "red"
            }
        }

        static func from(scoreDiff: Double) -> MoveQuality {
            switch scoreDiff {
            case ..<0.12:  return .optimal
            case ..<0.30:  return .excellent
            case ..<0.65:  return .good
            case ..<1.10:  return .inaccuracy
            case ..<2.00:  return .mistake
            default:       return .blunder
            }
        }
    }

    /// A single piece of coaching feedback with an SF Symbol icon, a short
    /// headline, and a fuller explanation of the underlying concept.
    struct CoachingTip: Identifiable {
        enum Category: String {
            case safety    = "Safety"
            case tactics   = "Tactics"
            case pointing  = "Key Points"
            case priming   = "Priming"
            case racing    = "Racing"
            case anchoring = "Anchoring"

            var sfSymbol: String {
                switch self {
                case .safety:    return "shield.fill"
                case .tactics:   return "target"
                case .pointing:  return "star.fill"
                case .priming:   return "rectangle.stack.fill"
                case .racing:    return "hare.fill"
                case .anchoring: return "anchor"
                }
            }
        }

        let id = UUID()
        let category: Category
        let headline: String
        let explanation: String
    }

    /// The result of comparing a player's completed turn against the optimal move.
    struct MoveAnalysis: Identifiable {
        let id = UUID()
        let quality: MoveQuality
        /// How many evaluation points better the optimal move was (0 = optimal).
        let scoreDiff: Double
        /// Specific coaching tips, ordered by importance (max 3).
        let tips: [CoachingTip]
        /// The board the engine would have reached — nil when player played optimally.
        let optimalBoard: BackgammonBoard?
    }

    // MARK: - Player Move Analysis

    /// Compares the board the player reached against what the engine would have
    /// played, then returns a `MoveAnalysis` with quality rating and targeted tips.
    ///
    /// - Parameters:
    ///   - boardBefore: Position at the start of the player's turn (before any moves).
    ///   - boardAfter:  Position after all of the player's moves were applied.
    ///   - dice:        The dice that were rolled for this turn.
    ///   - isWhite:     `true` when White (the human) just moved.
    static func analyzePlayerTurn(
        boardBefore: BackgammonBoard,
        boardAfter:  BackgammonBoard,
        dice:        [Int],
        isWhite:     Bool
    ) -> MoveAnalysis {

        // If there was only one legal move (or none), the player had no choice.
        let allSeqs = generateMoves(board: boardBefore, dice: dice, isWhite: isWhite)
        if allSeqs.count <= 1 {
            return MoveAnalysis(quality: .optimal, scoreDiff: 0, tips: [], optimalBoard: nil)
        }

        // Find the engine's best move and apply it to get the optimal board.
        let optimalSeq = chooseBestMove(board: boardBefore, dice: dice, isWhite: isWhite)
        var optimalBoard = boardBefore
        for m in optimalSeq.moves { optimalBoard = applyMove(m, to: optimalBoard, isWhite: isWhite) }

        // If the player reached the same position as the engine, it's optimal.
        if boardAfter == optimalBoard {
            return MoveAnalysis(quality: .optimal, scoreDiff: 0, tips: [], optimalBoard: nil)
        }

        // Score comparison with 1-ply eval (fast; sufficient for coaching context).
        let playerScore  = evaluate(boardAfter)
        let optimalScore = evaluate(optimalBoard)
        // From the player's perspective: positive diff = engine was better.
        let rawDiff = isWhite ? (optimalScore - playerScore) : (playerScore - optimalScore)
        let scoreDiff = max(0, rawDiff)

        let quality = MoveQuality.from(scoreDiff: scoreDiff)

        let tips = buildTips(
            boardBefore:  boardBefore,
            playerBoard:  boardAfter,
            optimalBoard: optimalBoard,
            isWhite:      isWhite,
            quality:      quality
        )

        return MoveAnalysis(
            quality:      quality,
            scoreDiff:    scoreDiff,
            tips:         tips,
            optimalBoard: scoreDiff >= 0.12 ? optimalBoard : nil
        )
    }

    // MARK: - Tip Generation

    private static func buildTips(
        boardBefore:  BackgammonBoard,
        playerBoard:  BackgammonBoard,
        optimalBoard: BackgammonBoard,
        isWhite:      Bool,
        quality:      MoveQuality
    ) -> [CoachingTip] {

        var tips: [CoachingTip] = []

        // Tip candidates in priority order: tactical > safety > strategic.
        let generators: [() -> CoachingTip?] = [
            { missedHitTip(before: boardBefore, player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
            { dangerousBlotTip(before: boardBefore, player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
            { missedKeyPointTip(before: boardBefore, player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
            { missedPrimeTip(before: boardBefore, player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
            { missedAnchorTip(before: boardBefore, player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
            { raceEfficiencyTip(player: playerBoard, optimal: optimalBoard, isWhite: isWhite) },
        ]

        for gen in generators {
            if tips.count >= 3 { break }
            if let tip = gen() { tips.append(tip) }
        }

        // Generic fallback when quality is poor but no specific pattern was found.
        if tips.isEmpty, quality == .mistake || quality == .blunder {
            tips.append(CoachingTip(
                category: .tactics,
                headline: "Look deeper before committing",
                explanation: "Before placing your checkers, scan for: hits (highest priority), point-making opportunities, and ways to avoid leaving blots. Doing this in order reveals the strongest play on most rolls."
            ))
        }

        return tips
    }

    // ── Tip: Missed hit ───────────────────────────────────────────────────────

    private static func missedHitTip(
        before: BackgammonBoard, player: BackgammonBoard,
        optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        let opBarBefore  = isWhite ? before.blackBar  : before.whiteBar
        let opBarPlayer  = isWhite ? player.blackBar  : player.whiteBar
        let opBarOptimal = isWhite ? optimal.blackBar : optimal.whiteBar

        // Optimal sent more opponent checkers to the bar than the player did.
        guard opBarOptimal > opBarPlayer else { return nil }

        // Find the point where the hit occurred in the optimal line.
        var hitIndex: Int? = nil
        for i in 0..<24 {
            let wasOpponentBlot = isWhite ? before.points[i] == -1 : before.points[i] == 1
            let optimalHit      = isWhite
                ? (optimal.points[i] > 0 && before.points[i] < 0)
                : (optimal.points[i] < 0 && before.points[i] > 0)
            if wasOpponentBlot && optimalHit { hitIndex = i; break }
        }

        let location = hitIndex.map { pointLabel($0, isWhite: isWhite) } ?? "an exposed checker"
        return CoachingTip(
            category: .tactics,
            headline: "Missed hit on \(location)",
            explanation: "Your opponent had a blot on \(location). Hitting it sends that checker to the bar, costing your opponent a full turn to re-enter — often the strongest play available, especially in the opening and midgame."
        )
    }

    // ── Tip: Dangerous blot ───────────────────────────────────────────────────

    private static func dangerousBlotTip(
        before: BackgammonBoard, player: BackgammonBoard,
        optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        // Blots the player has that the optimal move avoids.
        var avoidableBlots: [(index: Int, shots: Int, factor: Double)] = []
        for i in 0..<24 {
            let playerHasBlot  = isWhite ? player.points[i] == 1   : player.points[i] == -1
            let optimalHasBlot = isWhite ? optimal.points[i] == 1  : optimal.points[i] == -1
            guard playerHasBlot && !optimalHasBlot else { continue }
            let shots  = directShots(player, at: i, byBlack: isWhite)
            let factor = blotLocationFactor(i, isWhitePiece: isWhite)
            avoidableBlots.append((i, shots, factor))
        }

        guard !avoidableBlots.isEmpty else { return nil }

        // Report the most dangerous avoidable blot.
        let worst = avoidableBlots.max { a, b in a.factor * Double(a.shots) < b.factor * Double(b.shots) }!
        let shots = worst.shots

        // Only report if there are actual shots or it's in a very dangerous location.
        guard shots > 0 || worst.factor > 1.4 else { return nil }

        let pt = pointLabel(worst.index, isWhite: isWhite)
        let zone: String = worst.factor > 1.4
            ? "deep in your opponent's home board — very hard to re-enter from the bar"
            : (worst.factor > 1.1 ? "in the outfield" : "in your outer board")
        let shotText = shots == 0 ? "no direct shots now, but vulnerable to combination shots"
                                  : "\(shots) direct shot\(shots == 1 ? "" : "s") against it"

        return CoachingTip(
            category: .safety,
            headline: "Avoidable blot on \(pt)",
            explanation: "You left a checker exposed \(zone) with \(shotText). When a safer play exists, avoiding blots reduces your opponent's opportunities significantly."
        )
    }

    // ── Tip: Missed key point ─────────────────────────────────────────────────

    private static func missedKeyPointTip(
        before: BackgammonBoard, player: BackgammonBoard,
        optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        // Key point indices from this player's perspective, in priority order.
        // For White: 5-pt=4, bar-pt=6, opponent's 5-pt=19, opponent's 4-pt=18
        // For Black: 5-pt=19, bar-pt=17, opponent's 5-pt=4, opponent's 4-pt=5
        let keyPoints: [Int] = isWhite ? [4, 6, 19, 18] : [19, 17, 4, 5]

        for kp in keyPoints {
            let optimalOwns  = isWhite ? optimal.points[kp] >= 2  : optimal.points[kp] <= -2
            let playerOwns   = isWhite ? player.points[kp] >= 2   : player.points[kp] <= -2
            let ownedBefore  = isWhite ? before.points[kp] >= 2   : before.points[kp] <= -2
            guard optimalOwns && !playerOwns && !ownedBefore else { continue }

            let pt = pointLabel(kp, isWhite: isWhite)
            let reason: String
            let relIdx = isWhite ? kp : (23 - kp)
            switch relIdx {
            case 4:  reason = "the 5-point is the most prized piece of real estate in backgammon — it anchors your prime and blocks your opponent's key escape route"
            case 6:  reason = "the bar-point extends your prime toward a complete 6-prime, making it nearly impossible for trapped checkers to escape"
            case 18: reason = "an anchor in your opponent's home board keeps your back checkers safe and gives you a powerful staging point"
            case 19: reason = "securing your opponent's 5-point creates a golden anchor — safety, game-winning threats, and pressure all in one"
            default: reason = "this point strengthens your blockade and restricts your opponent's movement"
            }

            return CoachingTip(
                category: .pointing,
                headline: "Missed making \(pt)",
                explanation: "You had the checkers to make \(pt) — \(reason). Point-making is generally the second priority after hitting."
            )
        }
        return nil
    }

    // ── Tip: Missed prime extension ───────────────────────────────────────────

    private static func missedPrimeTip(
        before: BackgammonBoard, player: BackgammonBoard,
        optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        let beforePrime  = longestPrime(before,  isWhite: isWhite)
        let playerPrime  = longestPrime(player,  isWhite: isWhite)
        let optimalPrime = longestPrime(optimal, isWhite: isWhite)

        // Optimal extended the prime and player didn't, and the resulting prime
        // is at least 4 consecutive points (meaningful).
        guard optimalPrime > playerPrime,
              optimalPrime > beforePrime,
              optimalPrime >= 4 else { return nil }

        let adj = optimalPrime == 6 ? "a full 6-prime — completely unpassable" : "a \(optimalPrime)-point prime"
        return CoachingTip(
            category: .priming,
            headline: "Could have built \(adj)",
            explanation: "The better move creates \(adj). Any opponent checker trapped behind a 6-prime cannot escape until you break it, giving you complete control of the game's tempo."
        )
    }

    // ── Tip: Missed anchor ────────────────────────────────────────────────────

    private static func missedAnchorTip(
        before: BackgammonBoard, player: BackgammonBoard,
        optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        // Opponent's home board range.
        let oppHome = isWhite ? 18..<24 : 0..<6

        for i in oppHome {
            let optimalAnchored = isWhite ? optimal.points[i] >= 2 : optimal.points[i] <= -2
            let playerAnchored  = isWhite ? player.points[i] >= 2  : player.points[i] <= -2
            let anchoredBefore  = isWhite ? before.points[i] >= 2  : before.points[i] <= -2
            guard optimalAnchored && !playerAnchored && !anchoredBefore else { continue }

            let pt = pointLabel(i, isWhite: isWhite)
            return CoachingTip(
                category: .anchoring,
                headline: "Missed anchor on \(pt)",
                explanation: "Planting two checkers on \(pt) creates a secure anchor deep in enemy territory. Anchors serve a dual purpose: they protect your back runners from being hit, and they give you a re-entry point if your own checker is sent to the bar."
            )
        }
        return nil
    }

    // ── Tip: Race efficiency ──────────────────────────────────────────────────

    private static func raceEfficiencyTip(
        player: BackgammonBoard, optimal: BackgammonBoard, isWhite: Bool
    ) -> CoachingTip? {

        // Only meaningful in a pure race.
        guard !hasContact(player) && !hasContact(optimal) else { return nil }

        let playerPip  = isWhite ? whitePip(player)  : blackPip(player)
        let optimalPip = isWhite ? whitePip(optimal) : blackPip(optimal)
        let diff = playerPip - optimalPip  // positive = player's pip count is higher (worse)
        guard diff >= 2 else { return nil }

        return CoachingTip(
            category: .racing,
            headline: "Race efficiency: \(diff) pips wasted",
            explanation: "In a pure race the better move leaves you \(diff) fewer pips behind. Race strategy: move your most rearward checkers first (they cost the most if left behind), avoid over-stacking (3+ checkers on one point waste bear-off potential), and use every pip of every die."
        )
    }

    // ── Point label helper ────────────────────────────────────────────────────
    //
    // Returns a human-readable point name from the given player's perspective.
    // index 0-23, isWhite=true means White is the player being coached.

    static func pointLabel(_ index: Int, isWhite: Bool) -> String {
        // White's perspective: point numbers increase from 1 (White's ace-point, index 0)
        // to 24 (Black's ace-point, index 23).
        // Black's perspective: point numbers increase from 1 (Black's ace-point, index 23)
        // to 24 (White's ace-point, index 0).
        let myPoint = isWhite ? index + 1 : 24 - index  // 1-24 from this player's perspective

        // Special names for historically recognised key points.
        switch myPoint {
        case 1:  return "your ace-point"
        case 5:  return "your 5-point"
        case 7:  return "your bar-point"
        case 20: return "your opponent's 5-point"
        case 19: return "your opponent's 6-point"
        case 18: return "your opponent's 7-point"
        case 24: return "your opponent's ace-point"
        default:
            if myPoint <= 6  { return "your \(myPoint)-point" }
            if myPoint >= 19 { return "your opponent's \(25 - myPoint)-point" }
            return "the \(myPoint)-point"
        }
    }
}

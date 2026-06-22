import Foundation

// MARK: - Board

struct BackgammonBoard: Equatable, Hashable {
    var points: [Int] = Array(repeating: 0, count: 24)
    var whiteBar: Int = 0
    var blackBar: Int = 0
    var whiteOff: Int = 0
    var blackOff: Int = 0

    static let initial: BackgammonBoard = {
        var b = BackgammonBoard()
        b.points[0]  = -2
        b.points[5]  =  5
        b.points[7]  =  3
        b.points[11] = -5
        b.points[12] =  5
        b.points[16] = -3
        b.points[18] = -5
        b.points[23] =  2
        return b
    }()

    var whiteCanBearOff: Bool {
        whiteBar == 0 && (0..<18).allSatisfy { points[$0] >= 0 }
    }

    var blackCanBearOff: Bool {
        blackBar == 0 && (6..<24).allSatisfy { points[$0] <= 0 }
    }
}

// MARK: - Move types

struct CheckerMove: Hashable {
    let from: Int   // 0-23 or 24 = bar
    let to: Int     // 0-23 or 24 = bear-off
}

struct MoveSequence: Hashable {
    let moves: [CheckerMove]
}

// MARK: - Coaching types

enum MoveQuality: String, CaseIterable {
    case optimal, excellent, good, inaccuracy, mistake, blunder

    var label: String { rawValue.capitalized }

    var colorName: String {
        switch self {
        case .optimal:    return "green"
        case .excellent:  return "mint"
        case .good:       return "blue"
        case .inaccuracy: return "yellow"
        case .mistake:    return "orange"
        case .blunder:    return "red"
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

struct CoachingTip: Identifiable {
    enum Category: String {
        case safety, tactics, pointing, priming, racing, anchoring
        var sfSymbol: String {
            switch self {
            case .safety:    return "shield.fill"
            case .tactics:   return "target"
            case .pointing:  return "arrow.up.right.square.fill"
            case .priming:   return "lock.fill"
            case .racing:    return "hare.fill"
            case .anchoring: return "anchor.fill"
            }
        }
    }
    let id = UUID()
    let category: Category
    let headline: String
    let explanation: String
}

struct MoveAnalysis: Identifiable {
    let id = UUID()
    let quality: MoveQuality
    let scoreDiff: Double
    let tips: [CoachingTip]
    let optimalBoard: BackgammonBoard?
}

// MARK: - Engine

enum BackgammonEngine {

    // MARK: Move generation

    static func generateMoves(board: BackgammonBoard, dice: [Int], isWhite: Bool) -> [MoveSequence] {
        var results = Set<MoveSequence>()
        var best = 0
        expand(board: board, dice: dice, isWhite: isWhite, current: [], used: 0,
               depth: 0, best: &best, results: &results)
        if results.isEmpty { return [MoveSequence(moves: [])] }
        return Array(results)
    }

    private static func expand(board: BackgammonBoard, dice: [Int], isWhite: Bool,
                               current: [CheckerMove], used: Int, depth: Int,
                               best: inout Int, results: inout Set<MoveSequence>) {
        let achieved = current.count
        if achieved > best {
            best = achieved
            results.removeAll()
        }
        if achieved == best && achieved > 0 {
            results.insert(MoveSequence(moves: current))
        }

        for i in 0..<dice.count {
            if used & (1 << i) != 0 { continue }
            let die = dice[i]
            let singles = legalSingleMoves(board: board, die: die, isWhite: isWhite)
            for mv in singles {
                let nb = applyMove(mv, to: board, isWhite: isWhite)
                expand(board: nb, dice: dice, isWhite: isWhite,
                       current: current + [mv], used: used | (1 << i),
                       depth: depth + 1, best: &best, results: &results)
            }
        }
    }

    static func legalSingleMoves(board: BackgammonBoard, die: Int, isWhite: Bool) -> [CheckerMove] {
        var moves: [CheckerMove] = []
        if isWhite {
            // Bar entry: white enters on opponent's side (index 24-die)
            if board.whiteBar > 0 {
                let dest = 24 - die
                if dest >= 0 && board.points[dest] >= -1 {
                    moves.append(CheckerMove(from: 24, to: dest))
                }
                return moves
            }
            // Normal and exact-bear-off moves
            for i in 0..<24 where board.points[i] > 0 {
                let dest = i - die
                if dest >= 0 {
                    if board.points[dest] >= -1 {
                        moves.append(CheckerMove(from: i, to: dest))
                    }
                } else if board.whiteCanBearOff && dest == -1 {
                    // Exact bear-off (die exactly matches point number)
                    moves.append(CheckerMove(from: i, to: 24))
                }
            }
            // Overshoot bear-off: no checker at exact point or higher in home board
            if board.whiteCanBearOff {
                let exactIdx = die - 1  // index corresponding to exact match for this die
                let homeOccupied = (0..<6).filter { board.points[$0] > 0 }
                let hasExactOrHigher = homeOccupied.contains { $0 >= exactIdx }
                if !hasExactOrHigher, let highest = homeOccupied.max() {
                    let mv = CheckerMove(from: highest, to: 24)
                    if !moves.contains(mv) { moves.append(mv) }
                }
            }
        } else {
            // Bar entry: black enters on white's side (index die-1)
            if board.blackBar > 0 {
                let dest = die - 1
                if dest < 24 && board.points[dest] <= 1 {
                    moves.append(CheckerMove(from: 24, to: dest))
                }
                return moves
            }
            // Normal and exact-bear-off moves
            for i in 0..<24 where board.points[i] < 0 {
                let dest = i + die
                if dest < 24 {
                    if board.points[dest] <= 1 {
                        moves.append(CheckerMove(from: i, to: dest))
                    }
                } else if board.blackCanBearOff && dest == 24 {
                    // Exact bear-off
                    moves.append(CheckerMove(from: i, to: 24))
                }
            }
            // Overshoot bear-off: no checker at exact point or lower index in home
            if board.blackCanBearOff {
                let exactIdx = 24 - die  // index corresponding to exact match for this die
                let homeOccupied = (18..<24).filter { board.points[$0] < 0 }
                let hasExactOrLower = homeOccupied.contains { $0 <= exactIdx }
                if !hasExactOrLower, let highest = homeOccupied.max() {
                    let mv = CheckerMove(from: highest, to: 24)
                    if !moves.contains(mv) { moves.append(mv) }
                }
            }
        }
        return moves
    }

    static func applyMove(_ move: CheckerMove, to board: BackgammonBoard, isWhite: Bool) -> BackgammonBoard {
        var b = board
        if isWhite {
            if move.from == 24 { b.whiteBar -= 1 } else { b.points[move.from] -= 1 }
            if move.to == 24 {
                b.whiteOff += 1
            } else {
                if b.points[move.to] == -1 { b.points[move.to] = 0; b.blackBar += 1 }
                b.points[move.to] += 1
            }
        } else {
            if move.from == 24 { b.blackBar -= 1 } else { b.points[move.from] += 1 }
            if move.to == 24 {
                b.blackOff += 1
            } else {
                if b.points[move.to] == 1 { b.points[move.to] = 0; b.whiteBar += 1 }
                b.points[move.to] -= 1
            }
        }
        return b
    }

    // MARK: Evaluation

    static func evaluate(_ board: BackgammonBoard) -> Double {
        if board.whiteOff == 15 { return 100.0 }
        if board.blackOff == 15 { return -100.0 }
        return hasContact(board) ? contactEval(board) : raceEval(board)
    }

    static func hasContact(_ board: BackgammonBoard) -> Bool {
        guard let maxW = (0..<24).filter({ board.points[$0] > 0 }).max(),
              let minB = (0..<24).filter({ board.points[$0] < 0 }).min() else { return false }
        return maxW >= minB
    }

    private static func raceEval(_ board: BackgammonBoard) -> Double {
        var whitePip = 0, blackPip = 0
        for i in 0..<24 {
            if board.points[i] > 0 { whitePip += board.points[i] * (i + 1) }
            if board.points[i] < 0 { blackPip += (-board.points[i]) * (24 - i) }
        }
        whitePip += board.whiteBar * 25
        blackPip += board.blackBar * 25
        let diff = Double(blackPip - whitePip)
        return diff * 0.05
    }

    private static func contactEval(_ board: BackgammonBoard) -> Double {
        var score = 0.0
        // Pip differential
        var whitePip = 0, blackPip = 0
        for i in 0..<24 {
            if board.points[i] > 0 { whitePip += board.points[i] * (i + 1) }
            if board.points[i] < 0 { blackPip += (-board.points[i]) * (24 - i) }
        }
        whitePip += board.whiteBar * 25
        blackPip += board.blackBar * 25
        score += Double(blackPip - whitePip) * 0.035

        // Points owned
        for i in 0..<24 {
            let cnt = board.points[i]
            if cnt >= 2 { score += pointValue(i, isWhite: true) }
            if cnt <= -2 { score -= pointValue(i, isWhite: false) }
        }

        // Blot danger
        for i in 0..<24 {
            if board.points[i] == 1  { score -= 0.18 * blotLocationFactor(i, isWhitePiece: true) }
            if board.points[i] == -1 { score += 0.18 * blotLocationFactor(i, isWhitePiece: false) }
        }

        // Bar penalties
        score -= Double(board.whiteBar) * 0.65
        score += Double(board.blackBar) * 0.65

        // Prime bonus
        score += primeBonus(board: board, isWhite: true)
        score -= primeBonus(board: board, isWhite: false)

        // Home board strength
        var whiteHome = 0, blackHome = 0
        for i in 0..<6   where board.points[i] >= 2 { whiteHome += 1 }
        for i in 18..<24 where board.points[i] <= -2 { blackHome += 1 }
        score += Double(whiteHome) * 0.08
        score -= Double(blackHome) * 0.08

        return score
    }

    private static func pointValue(_ index: Int, isWhite: Bool) -> Double {
        if isWhite {
            switch index {
            case 4:  return 0.50   // white 5-point
            case 6:  return 0.38   // white bar-point
            case 3:  return 0.40   // white 4-point
            case 11: return 0.28   // white mid-point
            case 16: return 0.30   // opponent 8-point (anchor zone)
            case 18: return 0.35   // opponent 6-point
            case 20: return 0.32   // opponent 4-point
            default: return 0.18
            }
        } else {
            switch index {
            case 19: return 0.50   // black 5-point (mirror)
            case 17: return 0.38
            case 20: return 0.40
            case 12: return 0.28
            case 7:  return 0.30
            case 5:  return 0.35
            case 3:  return 0.32
            default: return 0.18
            }
        }
    }

    private static func blotLocationFactor(_ index: Int, isWhitePiece: Bool) -> Double {
        if isWhitePiece {
            switch index {
            case 18..<24: return 1.55  // deep in opponent home
            case 12..<18: return 1.20
            case 6..<12:  return 0.90
            default:      return 0.70
            }
        } else {
            switch index {
            case 0..<6:   return 1.55
            case 6..<12:  return 1.20
            case 12..<18: return 0.90
            default:      return 0.70
            }
        }
    }

    private static func primeBonus(board: BackgammonBoard, isWhite: Bool) -> Double {
        var maxRun = 0, cur = 0
        for i in 0..<24 {
            let hasPoint = isWhite ? board.points[i] >= 2 : board.points[i] <= -2
            if hasPoint { cur += 1; maxRun = max(maxRun, cur) } else { cur = 0 }
        }
        return maxRun >= 4 ? Double(maxRun - 3) * 0.25 : 0
    }

    // MARK: AI move selection

    static func chooseBestMove(board: BackgammonBoard, dice: [Int], isWhite: Bool,
                               skill: Double = 1.0) -> MoveSequence {
        let candidates = generateMoves(board: board, dice: dice, isWhite: isWhite)
        guard !candidates.isEmpty else { return MoveSequence(moves: []) }
        if candidates.count == 1 { return candidates[0] }

        let scored: [(MoveSequence, Double)] = candidates.map { seq in
            let nb = applySequence(seq, to: board, isWhite: isWhite)
            let s = isWhite ? evaluate(nb) : -evaluate(nb)
            return (seq, s)
        }

        if skill >= 0.98 {
            let top = scored.sorted { $0.1 > $1.1 }
            return expectimaxPick(from: top, board: board, isWhite: isWhite)
        } else if skill >= 0.65 {
            let top16 = scored.sorted { $0.1 > $1.1 }.prefix(16)
            let seqs   = top16.map { $0.0 }
            let scores = top16.map { $0.1 }
            let exScores: [Double] = seqs.map { seq in
                let nb = applySequence(seq, to: board, isWhite: isWhite)
                return expectedOpponentScore(after: nb, opponentIsWhite: !isWhite)
            }
            let combined = zip(scores, exScores).map { $0 - $1 * 0.5 }
            return softmaxSample(items: seqs, scores: combined,
                                 temperature: temperatureForSkill(skill))
        } else {
            let seqs   = scored.map { $0.0 }
            let scores = scored.map { $0.1 }
            return softmaxSample(items: seqs, scores: scores,
                                 temperature: temperatureForSkill(skill))
        }
    }

    private static func expectimaxPick(from sorted: [(MoveSequence, Double)],
                                       board: BackgammonBoard, isWhite: Bool) -> MoveSequence {
        let top = sorted.prefix(8)
        var best: MoveSequence = sorted[0].0
        var bestEx = -Double.infinity
        for (seq, _) in top {
            let nb = applySequence(seq, to: board, isWhite: isWhite)
            let ex = -expectedOpponentScore(after: nb, opponentIsWhite: !isWhite)
            if ex > bestEx { bestEx = ex; best = seq }
        }
        return best
    }

    static func expectedOpponentScore(after board: BackgammonBoard,
                                      opponentIsWhite: Bool) -> Double {
        var total = 0.0
        var weight = 0.0
        for d1 in 1...6 {
            for d2 in d1...6 {
                let w = d1 == d2 ? 1.0/36.0 : 2.0/36.0
                let dice = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
                let cands = generateMoves(board: board, dice: dice, isWhite: opponentIsWhite)
                let best = cands.map { seq -> Double in
                    let nb = applySequence(seq, to: board, isWhite: opponentIsWhite)
                    return opponentIsWhite ? evaluate(nb) : -evaluate(nb)
                }.max() ?? 0
                total += w * best
                weight += w
            }
        }
        return total / weight
    }

    private static func temperatureForSkill(_ skill: Double) -> Double {
        0.2 + 8.0 * pow(1.0 - skill, 1.5)
    }

    private static func softmaxSample(items: [MoveSequence], scores: [Double],
                                      temperature: Double) -> MoveSequence {
        let scaled = scores.map { $0 / temperature }
        let maxS = scaled.max() ?? 0
        let exps = scaled.map { exp($0 - maxS) }
        let sum = exps.reduce(0, +)
        let probs = exps.map { $0 / sum }
        let r = Double.random(in: 0..<1)
        var cum = 0.0
        for (i, p) in probs.enumerated() {
            cum += p
            if r < cum { return items[i] }
        }
        return items.last!
    }

    static func applySequence(_ seq: MoveSequence, to board: BackgammonBoard,
                              isWhite: Bool) -> BackgammonBoard {
        var b = board
        for mv in seq.moves { b = applyMove(mv, to: b, isWhite: isWhite) }
        return b
    }

    // MARK: Coaching

    static func analyzePlayerTurn(boardBefore: BackgammonBoard, boardAfter: BackgammonBoard,
                                  dice: [Int], isWhite: Bool) -> MoveAnalysis {
        let allMoves = generateMoves(board: boardBefore, dice: dice, isWhite: isWhite)
        let scored: [(MoveSequence, Double)] = allMoves.map { seq in
            let nb = applySequence(seq, to: boardBefore, isWhite: isWhite)
            let s = isWhite ? evaluate(nb) : -evaluate(nb)
            return (seq, s)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else {
            return MoveAnalysis(quality: .optimal, scoreDiff: 0, tips: [], optimalBoard: nil)
        }

        let playerScore: Double = {
            let s = isWhite ? evaluate(boardAfter) : -evaluate(boardAfter)
            return s
        }()

        let diff = max(0, best.1 - playerScore)
        let quality = MoveQuality.from(scoreDiff: diff)
        let optimalBoard = quality == .optimal ? nil : applySequence(best.0, to: boardBefore, isWhite: isWhite)

        var tips: [CoachingTip] = []
        let detectors: [(BackgammonBoard, BackgammonBoard, BackgammonBoard, [Int], Bool) -> CoachingTip?] = [
            missedHitTip, dangerousBlotTip, missedKeyPointTip,
            missedPrimeTip, missedAnchorTip, raceEfficiencyTip
        ]
        for det in detectors {
            if let t = det(boardBefore, boardAfter, optimalBoard ?? boardAfter, dice, isWhite) {
                tips.append(t)
                if tips.count == 3 { break }
            }
        }

        return MoveAnalysis(quality: quality, scoreDiff: diff, tips: tips, optimalBoard: optimalBoard)
    }

    private static func missedHitTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                     _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        let opBar = isWhite ? optimal.blackBar : optimal.whiteBar
        let pBar  = isWhite ? after.blackBar   : after.whiteBar
        guard opBar > pBar else { return nil }
        return CoachingTip(category: .tactics,
                           headline: "Missed opportunity to hit a blot",
                           explanation: "The best move would have sent an opponent's checker to the bar. Hitting blots forces your opponent to waste turns re-entering from the bar, and a checker on the bar threatens no one.")
    }

    private static func dangerousBlotTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                         _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        let myBlots = countBlots(after, isWhite: isWhite)
        let optBlots = countBlots(optimal, isWhite: isWhite)
        guard myBlots > optBlots + 1 else { return nil }
        return CoachingTip(category: .safety,
                           headline: "Left too many checkers exposed",
                           explanation: "You left \(myBlots) unprotected checkers (blots) compared to \(optBlots) in the best line. Each blot is a target. Pair checkers to make points, or land in safe zones behind your opponent's prime.")
    }

    private static func missedKeyPointTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                          _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        let keyPoints: [Int] = isWhite ? [4, 6, 3] : [19, 17, 20]
        for pt in keyPoints {
            let optOwns = isWhite ? optimal.points[pt] >= 2 : optimal.points[pt] <= -2
            let playerOwns = isWhite ? after.points[pt] >= 2 : after.points[pt] <= -2
            let beforeOwns = isWhite ? before.points[pt] >= 2 : before.points[pt] <= -2
            if optOwns && !playerOwns && !beforeOwns {
                return CoachingTip(category: .pointing,
                                   headline: "Missed a chance to make the \(pointLabel(pt, isWhite: isWhite))",
                                   explanation: "The \(pointLabel(pt, isWhite: isWhite)) is a key strategic point. Owning it blocks opponent runners and provides a strong launching pad. The best move would have secured it this turn.")
            }
        }
        return nil
    }

    private static func missedPrimeTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                       _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        func primeLen(_ b: BackgammonBoard) -> Int {
            var maxRun = 0, cur = 0
            for i in 0..<24 {
                let owns = isWhite ? b.points[i] >= 2 : b.points[i] <= -2
                if owns { cur += 1; maxRun = max(maxRun, cur) } else { cur = 0 }
            }
            return maxRun
        }
        let optPrime = primeLen(optimal)
        let myPrime  = primeLen(after)
        guard optPrime >= 4 && myPrime < optPrime - 1 else { return nil }
        return CoachingTip(category: .priming,
                           headline: "Missed a chance to extend your prime",
                           explanation: "A prime is a consecutive run of points you own. The best move would have built a \(optPrime)-point prime. A 6-point prime is unpassable — your opponent's checkers are completely trapped until you move.")
    }

    private static func missedAnchorTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                        _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        let anchorZone: [Int] = isWhite ? [18, 19, 20] : [3, 4, 5]
        for pt in anchorZone {
            let optHasAnchor  = isWhite ? optimal.points[pt] <= -2 : optimal.points[pt] >= 2
            let playerHasAnchor = isWhite ? after.points[pt] <= -2 : after.points[pt] >= 2
            let beforeHasAnchor = isWhite ? before.points[pt] <= -2 : before.points[pt] >= 2
            if optHasAnchor && !playerHasAnchor && !beforeHasAnchor {
                return CoachingTip(category: .anchoring,
                                   headline: "Missed chance to establish an anchor",
                                   explanation: "An anchor is two or more of your checkers deep in your opponent's home board. Anchors give you a safe landing zone, threaten hit-and-run counterplay, and make it safer to leave blots elsewhere.")
            }
        }
        return nil
    }

    private static func raceEfficiencyTip(_ before: BackgammonBoard, _ after: BackgammonBoard,
                                          _ optimal: BackgammonBoard, _ dice: [Int], _ isWhite: Bool) -> CoachingTip? {
        guard !hasContact(after) else { return nil }
        func pipCount(_ b: BackgammonBoard) -> Int {
            var pip = 0
            for i in 0..<24 {
                if isWhite && b.points[i] > 0 { pip += b.points[i] * (i + 1) }
                if !isWhite && b.points[i] < 0 { pip += (-b.points[i]) * (24 - i) }
            }
            return pip
        }
        let optPip  = pipCount(optimal)
        let myPip   = pipCount(after)
        guard myPip > optPip + 2 else { return nil }
        return CoachingTip(category: .racing,
                           headline: "Inefficient move in a pure race",
                           explanation: "No contact remains — this is a pure pip race. The best move saves \(myPip - optPip) extra pips. In a race, prioritize bearing off efficiently and avoid stacking checkers on high points when low points are open.")
    }

    private static func countBlots(_ board: BackgammonBoard, isWhite: Bool) -> Int {
        if isWhite { return (0..<24).filter { board.points[$0] == 1 }.count }
        else       { return (0..<24).filter { board.points[$0] == -1 }.count }
    }

    static func pointLabel(_ index: Int, isWhite: Bool) -> String {
        let num = isWhite ? index + 1 : 24 - index
        let isYours = isWhite ? num <= 6 : num >= 19
        switch num {
        case 5:  return isYours ? "your 5-point"         : "opponent's 5-point"
        case 7:  return isYours ? "your bar-point"       : "opponent's bar-point"
        case 4:  return isYours ? "your 4-point"         : "opponent's 4-point"
        case 13: return "mid-point"
        default:
            let pos = num <= 12 ? "your \(num)-point" : "opponent's \(24-num+1)-point"
            return pos
        }
    }

    // MARK: Dice-first input helper

    /// Given a destination point index, a die value, and the current board,
    /// finds a legal checker that can move to `dest` using `die`.
    /// Returns the source point if exactly one legal source exists (or best unique).
    static func findSourceForDest(board: BackgammonBoard, dest: Int, die: Int,
                                  isWhite: Bool) -> Int? {
        let singles = legalSingleMoves(board: board, die: die, isWhite: isWhite)
        let matching = singles.filter { $0.to == dest }
        if matching.isEmpty { return nil }
        if matching.count == 1 { return matching[0].from }
        // Multiple checkers can reach — prefer bar, then outermost
        if let barMove = matching.first(where: { $0.from == 24 }) { return barMove.from }
        if isWhite { return matching.max(by: { $0.from < $1.from })?.from }
        else       { return matching.min(by: { $0.from < $1.from })?.from }
    }
}

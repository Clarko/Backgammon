// BoardView.swift
// Full backgammon board rendered in SwiftUI.
//
// Layout (White = cream circles, Black = dark circles):
//   TOP ROW    (points 13-18, then 19-24)  — checkers hang downward
//   BOTTOM ROW (points 12-7,  then  6-1)   — checkers hang upward
//   Bar splits each half. Bear-off trays on the right.

import SwiftUI

// MARK: - Constants
private let pointCount   = 24
private let pointWidth   : CGFloat = 44
private let boardPad     : CGFloat = 8
private let checkerSize  : CGFloat = 36
private let barWidth     : CGFloat = 40
private let bearOffWidth : CGFloat = 50

// MARK: - Main Board View

struct BoardView: View {
    @ObservedObject var gameState: GameState
    @State private var showingCoach = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Felt background
                Color(red: 0.15, green: 0.45, blue: 0.25)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status bar
                    statusBar
                        .frame(height: 50)

                    // Board area
                    HStack(spacing: 0) {
                        boardBody
                        bearOffTray
                    }
                    .padding(.horizontal, boardPad)

                    // Control bar
                    controlBar
                        .frame(height: 80)
                }
            }
        }
        // Show coaching sheet when a new analysis arrives.
        .onChange(of: gameState.coachingAnalysis?.id) { _ in
            if gameState.coachingAnalysis != nil { showingCoach = true }
        }
        // Auto-dismiss if the player starts a new turn before tapping Done.
        .onChange(of: gameState.phase) { phase in
            if case .moving = phase { showingCoach = false }
        }
        .sheet(isPresented: $showingCoach) {
            if let analysis = gameState.coachingAnalysis {
                CoachingSheetView(analysis: analysis) { showingCoach = false }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(gameState.message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
            if !gameState.dice.isEmpty {
                DiceRowView(dice: gameState.dice, usedDice: gameState.usedDice)
                    .padding(.trailing, 12)
            }
        }
        .background(Color.black.opacity(0.30))
    }

    // MARK: - Board Body

    private var boardBody: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let halfH = h / 2

            ZStack(alignment: .top) {
                // Outer frame
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.55, green: 0.27, blue: 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(red: 0.35, green: 0.18, blue: 0.04), lineWidth: 3)
                    )

                HStack(spacing: 0) {
                    // Left half (points 13-18 top / 12-7 bottom)
                    halfBoard(topPoints: Array(12...17),
                              bottomPoints: Array(stride(from: 11, through: 6, by: -1)),
                              height: h)

                    // Bar
                    barColumn(height: h)

                    // Right half (points 19-24 top / 6-1 bottom)
                    halfBoard(topPoints: Array(18...23),
                              bottomPoints: Array(stride(from: 5, through: 0, by: -1)),
                              height: h)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    /// Renders 6 point columns for a half of the board.
    private func halfBoard(topPoints: [Int], bottomPoints: [Int], height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(topPoints.indices, id: \.self) { col in
                let topIdx  = topPoints[col]
                let botIdx  = bottomPoints[col]
                let isEven  = col % 2 == 0

                ZStack(alignment: .top) {
                    // Triangle background
                    VStack(spacing: 0) {
                        TriangleShape(pointingDown: false)
                            .fill(isEven
                                  ? Color(red: 0.75, green: 0.12, blue: 0.12)
                                  : Color(red: 0.92, green: 0.80, blue: 0.55))
                            .frame(height: height / 2)

                        TriangleShape(pointingDown: true)
                            .fill(isEven
                                  ? Color(red: 0.92, green: 0.80, blue: 0.55)
                                  : Color(red: 0.75, green: 0.12, blue: 0.12))
                            .frame(height: height / 2)
                    }

                    // Top point checkers (hang downward)
                    pointColumn(index: topIdx, fromTop: true, height: height / 2)
                        .frame(height: height / 2)
                        .frame(maxHeight: .infinity, alignment: .top)

                    // Bottom point checkers (hang upward)
                    pointColumn(index: botIdx, fromTop: false, height: height / 2)
                        .frame(height: height / 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    // Point number labels
                    VStack {
                        pointLabel(topIdx + 1)
                            .frame(maxHeight: .infinity, alignment: .top)
                        pointLabel(botIdx + 1)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: pointWidth)
                .contentShape(Rectangle())
                .onTapGesture { handleTap(index: topIdx, isTop: true, otherIndex: botIdx) }
            }
        }
    }

    private func handleTap(index: Int, isTop: Bool, otherIndex: Int) {
        // Determine which point was actually tapped based on checker presence
        let isWhite = gameState.currentPlayer == .white
        let board   = gameState.board

        // Top points: tap selects/moves top or bottom depending on checker + valid dest
        for idx in [index, otherIndex] {
            if gameState.validDestinations.contains(idx) {
                gameState.selectPoint(idx)
                return
            }
        }
        // Try selecting a checker
        for idx in [index, otherIndex] {
            let hasChecker = isWhite ? board.points[idx] > 0 : board.points[idx] < 0
            if hasChecker {
                gameState.selectPoint(idx)
                return
            }
        }
    }

    // MARK: - Single Point Column

    private func pointColumn(index: Int, fromTop: Bool, height: CGFloat) -> some View {
        let count    = abs(gameState.board.points[index])
        let isWhite  = gameState.board.points[index] > 0
        let isSelected   = gameState.selectedPoint == index
        let isValidDest  = gameState.validDestinations.contains(index)
        let maxVisible   = min(count, 5)

        return ZStack(alignment: fromTop ? .top : .bottom) {
            // Highlight ring
            if isSelected || isValidDest {
                Rectangle()
                    .fill(isSelected
                          ? Color.yellow.opacity(0.35)
                          : Color.green.opacity(0.25))
            }

            VStack(spacing: 1) {
                let checkers = fromTop
                    ? Array((0..<maxVisible))
                    : Array((0..<maxVisible).reversed())

                ForEach(checkers, id: \.self) { i in
                    checkerView(isWhite: isWhite, isSelected: isSelected && i == 0)
                }
                if count > 5 {
                    Text("+\(count - 5)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, 2)
        }
        .onTapGesture { gameState.selectPoint(index) }
    }

    // MARK: - Bar Column

    private func barColumn(height: CGFloat) -> some View {
        let board = gameState.board
        let wBar  = board.whiteBar
        let bBar  = board.blackBar
        let isWhiteTurn = gameState.currentPlayer == .white

        return ZStack {
            Color(red: 0.50, green: 0.25, blue: 0.05)

            VStack(spacing: 4) {
                // Black checkers on bar (top half of bar)
                VStack(spacing: 1) {
                    ForEach(0..<min(bBar, 4), id: \.self) { _ in
                        checkerView(isWhite: false, isSelected: false)
                    }
                    if bBar > 4 { Text("+\(bBar-4)").font(.system(size: 9, weight: .bold)).foregroundColor(.white) }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { if !isWhiteTurn { gameState.selectPoint(24) } }

                Divider().background(Color.white.opacity(0.4))

                Text("BAR").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.6))

                Divider().background(Color.white.opacity(0.4))

                // White checkers on bar (bottom half of bar)
                VStack(spacing: 1) {
                    ForEach(0..<min(wBar, 4), id: \.self) { _ in
                        checkerView(isWhite: true, isSelected: false)
                    }
                    if wBar > 4 { Text("+\(wBar-4)").font(.system(size: 9, weight: .bold)).foregroundColor(.white) }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { if isWhiteTurn { gameState.selectPoint(24) } }
            }
            .padding(.vertical, 6)
        }
        .frame(width: barWidth)
    }

    // MARK: - Bear-off Tray

    private var bearOffTray: some View {
        let board = gameState.board

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.40, green: 0.20, blue: 0.04))

            VStack(spacing: 6) {
                // Black bear-off (top)
                VStack(spacing: 2) {
                    Text("BLACK").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                    Text("\(board.blackOff)").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    ForEach(0..<min(board.blackOff, 6), id: \.self) { _ in
                        checkerView(isWhite: false, isSelected: false)
                            .scaleEffect(0.7)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Divider().background(Color.white.opacity(0.3))

                // White bear-off (bottom)
                VStack(spacing: 2) {
                    Text("WHITE").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                    Text("\(board.whiteOff)").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    ForEach(0..<min(board.whiteOff, 6), id: \.self) { _ in
                        checkerView(isWhite: true, isSelected: false)
                            .scaleEffect(0.7)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(6)
        }
        .frame(width: bearOffWidth)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 20) {
            // Roll button (visible on White's rolling phase)
            if case .rolling = gameState.phase {
                Button(action: { gameState.rollDice() }) {
                    Text("Roll Dice")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.18, green: 0.55, blue: 0.34))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                }
            }

            // New Game (always available when game over)
            if case .gameOver(_) = gameState.phase {
                Button(action: { gameState.newGame() }) {
                    Text("New Game")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .shadow(radius: 4)
                }
            }

            // Coach button — reopen the last analysis if dismissed early
            if let analysis = gameState.coachingAnalysis, !showingCoach {
                Button(action: { showingCoach = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                        Text(analysis.quality.label)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(coachButtonColor(analysis.quality))
                    .cornerRadius(8)
                    .shadow(radius: 3)
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Pip counts
            pipCountView
        }
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.35))
        .animation(.easeInOut(duration: 0.2), value: gameState.coachingAnalysis?.id)
    }

    private func coachButtonColor(_ quality: BackgammonEngine.MoveQuality) -> Color {
        switch quality {
        case .optimal, .excellent: return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .good:                return Color(red: 0.0,  green: 0.45, blue: 0.45)
        case .inaccuracy:          return Color(red: 0.65, green: 0.50, blue: 0.0)
        case .mistake:             return Color(red: 0.75, green: 0.35, blue: 0.0)
        case .blunder:             return Color(red: 0.75, green: 0.10, blue: 0.10)
        }
    }

    private var pipCountView: some View {
        VStack(alignment: .leading, spacing: 2) {
            pipLabel(label: "White pip:", value: whitePip())
            pipLabel(label: "Black pip:", value: blackPip())
        }
    }

    private func pipLabel(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text("\(value)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
        }
    }

    // MARK: - Checker View

    private func checkerView(isWhite: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isWhite
                      ? Color(red: 0.95, green: 0.90, blue: 0.80)
                      : Color(red: 0.15, green: 0.10, blue: 0.10))
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)

            Circle()
                .stroke(isSelected
                        ? Color.yellow
                        : (isWhite ? Color(red: 0.7, green: 0.6, blue: 0.4)
                                   : Color(red: 0.4, green: 0.3, blue: 0.3)),
                        lineWidth: isSelected ? 2.5 : 1)

            if isSelected {
                Circle().fill(Color.yellow.opacity(0.3))
            }
        }
        .frame(width: checkerSize, height: checkerSize)
    }

    // MARK: - Point Number Label

    private func pointLabel(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.white.opacity(0.55))
            .padding(1)
    }

    // MARK: - Pip Count Helpers

    private func whitePip() -> Int {
        let b = gameState.board
        var p = b.whiteBar * 25
        for i in 0..<24 where b.points[i] > 0 { p += b.points[i] * (i + 1) }
        return p
    }

    private func blackPip() -> Int {
        let b = gameState.board
        var p = b.blackBar * 25
        for i in 0..<24 where b.points[i] < 0 { p += (-b.points[i]) * (24 - i) }
        return p
    }
}

// MARK: - Triangle Shape

struct TriangleShape: Shape {
    let pointingDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

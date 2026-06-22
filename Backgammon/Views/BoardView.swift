import SwiftUI

// MARK: - Layout constants computed from available size

struct BoardLayout {
    let pointWidth: CGFloat
    let checkerSize: CGFloat
    let barWidth: CGFloat
    let bearOffWidth: CGFloat
    let boardHeight: CGFloat

    init(availableWidth: CGFloat, availableHeight: CGFloat) {
        bearOffWidth  = max(34, availableWidth * 0.072)
        // Total board area (12 points + bar) within padding
        let boardArea = availableWidth - bearOffWidth - 16   // 8pt each side
        barWidth      = max(24, boardArea * 0.055)
        pointWidth    = (boardArea - barWidth) / 12
        checkerSize   = min(pointWidth * 0.86, 38)
        boardHeight   = availableHeight
    }
}

// MARK: - BoardView

struct BoardView: View {
    @ObservedObject var gameState: GameState
    @State private var showingCoach = false
    @State private var showingDifficulty = false

    private let statusH:  CGFloat = 54
    private let controlH: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let boardAvailH = geo.size.height - statusH - controlH
            let layout = BoardLayout(availableWidth: geo.size.width,
                                     availableHeight: boardAvailH)
            ZStack {
                Color(red: 0.15, green: 0.45, blue: 0.25).ignoresSafeArea()
                VStack(spacing: 0) {
                    statusBar
                        .frame(height: statusH)
                    HStack(alignment: .top, spacing: 0) {
                        fullBoard(layout: layout)
                        bearOffTray(layout: layout)
                    }
                    .padding(.horizontal, 8)
                    controlBar
                        .frame(height: controlH)
                }
            }
        }
        .onChange(of: gameState.coachingAnalysis?.id) { _ in
            if gameState.coachingAnalysis != nil { showingCoach = true }
        }
        .onChange(of: gameState.phase) { phase in
            if phase == .moving { showingCoach = false }
        }
        .sheet(isPresented: $showingCoach) {
            if let analysis = gameState.coachingAnalysis {
                CoachingSheetView(analysis: analysis) { showingCoach = false }
            }
        }
        .sheet(isPresented: $showingDifficulty) {
            DifficultySheetView(gameState: gameState) { showingDifficulty = false }
        }
    }

    // MARK: Full board (left 6 | bar | right 6)

    @ViewBuilder
    private func fullBoard(layout: BoardLayout) -> some View {
        let halfH = layout.boardHeight / 2
        ZStack {
            // Wood background
            Color(red: 0.55, green: 0.27, blue: 0.07)

            VStack(spacing: 0) {
                // Top row of points: indices 12..23 left-to-right (black's home → white's outer)
                HStack(spacing: 0) {
                    // Left 6: indices 12-17
                    ForEach(12..<18, id: \.self) { i in
                        pointView(index: i, isTop: true, layout: layout)
                            .frame(width: layout.pointWidth, height: halfH)
                    }
                    // Bar (top)
                    barHalf(isTop: true, layout: layout)
                        .frame(width: layout.barWidth, height: halfH)
                    // Right 6: indices 18-23
                    ForEach(18..<24, id: \.self) { i in
                        pointView(index: i, isTop: true, layout: layout)
                            .frame(width: layout.pointWidth, height: halfH)
                    }
                }
                .frame(height: halfH)

                // Centre divider
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(height: 2)

                // Bottom row: indices 11..0 left-to-right
                HStack(spacing: 0) {
                    ForEach((6..<12).reversed(), id: \.self) { i in
                        pointView(index: i, isTop: false, layout: layout)
                            .frame(width: layout.pointWidth, height: halfH)
                    }
                    barHalf(isTop: false, layout: layout)
                        .frame(width: layout.barWidth, height: halfH)
                    ForEach((0..<6).reversed(), id: \.self) { i in
                        pointView(index: i, isTop: false, layout: layout)
                            .frame(width: layout.pointWidth, height: halfH)
                    }
                }
                .frame(height: halfH)
            }
        }
        .frame(width: layout.pointWidth * 12 + layout.barWidth, height: layout.boardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Point view

    @ViewBuilder
    private func pointView(index: Int, isTop: Bool, layout: BoardLayout) -> some View {
        let isHighlighted = gameState.validDestinations.contains(index)
        let isSelected    = gameState.selectedPoint == index
        let count         = gameState.pendingBoard.points[index]
        let isWhiteChecker = count > 0
        let absCount      = abs(count)

        ZStack {
            // Triangle
            TriangleShape(pointingDown: isTop)
                .fill(isHighlighted ? Color.yellow : triangleColor(index: index))
                .opacity(isHighlighted ? 0.85 : 1.0)

            // Checkers
            let maxVis  = 5
            let dispCnt = min(absCount, maxVis)
            let shrink  = absCount > maxVis
            let sz      = shrink ? layout.checkerSize * 0.76 : layout.checkerSize

            if isTop {
                VStack(spacing: 1) {
                    ForEach(0..<dispCnt, id: \.self) { i in
                        checkerView(isWhite: isWhiteChecker, size: sz,
                                    showLabel: shrink && i == dispCnt - 1,
                                    label: "\(absCount)")
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    ForEach(0..<dispCnt, id: \.self) { i in
                        checkerView(isWhite: isWhiteChecker, size: sz,
                                    showLabel: shrink && i == 0,
                                    label: "\(absCount)")
                    }
                }
            }

            // Selected highlight
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow, lineWidth: 3)
            }

            // Destination indicator (when no checker there yet)
            if isHighlighted && absCount == 0 {
                Circle()
                    .fill(Color.yellow.opacity(0.6))
                    .frame(width: layout.checkerSize * 0.42, height: layout.checkerSize * 0.42)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap(index: index) }
    }

    @ViewBuilder
    private func checkerView(isWhite: Bool, size: CGFloat, showLabel: Bool, label: String) -> some View {
        ZStack {
            Circle()
                .fill(isWhite ? Color.white : Color.black)
                .frame(width: size, height: size)
            Circle()
                .stroke(isWhite ? Color.gray.opacity(0.6) : Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: size, height: size)
            if showLabel {
                Text(label)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(isWhite ? .black : .white)
            }
        }
    }

    // MARK: Bar halves

    @ViewBuilder
    private func barHalf(isTop: Bool, layout: BoardLayout) -> some View {
        let board = gameState.pendingBoard
        let count = isTop ? board.blackBar : board.whiteBar
        let isWhite = !isTop

        ZStack {
            Color(red: 0.32, green: 0.14, blue: 0.03)
            VStack(spacing: 2) {
                if !isTop { Spacer() }
                ForEach(0..<min(count, 4), id: \.self) { _ in
                    checkerView(isWhite: isWhite, size: layout.checkerSize * 0.78,
                                showLabel: false, label: "")
                }
                if count > 4 {
                    Text("+\(count - 4)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                if isTop { Spacer() }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if gameState.phase == .moving && !isTop && board.whiteBar > 0 {
                gameState.selectPoint(24)
            }
        }
    }

    // MARK: Bear-off tray

    @ViewBuilder
    private func bearOffTray(layout: BoardLayout) -> some View {
        let halfH = layout.boardHeight / 2
        VStack(spacing: 0) {
            // AI (black) borne off
            VStack(spacing: 4) {
                Text("AI")
                    .font(.caption2).foregroundColor(.white).opacity(0.6)
                Text("\(gameState.board.blackOff)")
                    .font(.title3.bold()).foregroundColor(.white)
                Spacer()
            }
            .frame(height: halfH)

            // Player (white) borne off
            VStack(spacing: 4) {
                Spacer()
                Text("\(gameState.board.whiteOff)")
                    .font(.title3.bold()).foregroundColor(.white)
                Text("You")
                    .font(.caption2).foregroundColor(.white).opacity(0.6)
            }
            .frame(height: halfH)
        }
        .frame(width: layout.bearOffWidth, height: layout.boardHeight)
        .background(Color(red: 0.10, green: 0.32, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Status bar

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("You: \(pipCount(isWhite: true))").font(.caption2)
                Text("AI: \(pipCount(isWhite: false))").font(.caption2)
            }
            .foregroundColor(.white)
            .opacity(0.75)
            .frame(width: 72, alignment: .leading)

            Spacer()

            Text(gameState.message)
                .font(.caption.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Spacer()

            HStack(spacing: 10) {
                if let analysis = gameState.coachingAnalysis {
                    Button {
                        showingCoach = true
                    } label: {
                        Text(analysis.quality.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(qualityColor(analysis.quality))
                            .foregroundColor(.white)
                            .cornerRadius(7)
                    }
                }
                Button {
                    showingDifficulty = true
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "gearshape.fill").font(.caption)
                        Text(gameState.isAdaptiveAI ? "Dynamic" : gameState.aiSkillLabel)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white)
                    .opacity(0.8)
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.2))
    }

    // MARK: Control bar

    @ViewBuilder
    private var controlBar: some View {
        VStack(spacing: 6) {
            // Dice display
            if !gameState.dice.isEmpty {
                DiceRowView(
                    dice: gameState.dice,
                    usedDice: gameState.usedDice,
                    diceFirstMode: gameState.inputMode == .diceFirst,
                    selectedDieIndex: gameState.selectedDieIndex,
                    onDieTap: { i in gameState.selectDie(i) }
                )
            }

            // Action buttons
            HStack(spacing: 12) {
                switch gameState.phase {
                case .rolling:
                    rollButton
                case .moving:
                    undoButton
                    doneButton
                case .aiTurn:
                    Text("AI thinking…")
                        .font(.headline)
                        .foregroundColor(.white)
                        .opacity(0.65)
                case .gameOver:
                    newGameButton(primary: true)
                }

                if gameState.phase == .rolling || gameState.phase == .moving {
                    newGameButton(primary: false)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.28))
    }

    private var rollButton: some View {
        Button("Roll Dice") { gameState.rollDice() }
            .buttonStyle(ActionButtonStyle(color: .blue))
    }

    private var undoButton: some View {
        Button("Undo") { gameState.undoLastMove() }
            .buttonStyle(ActionButtonStyle(color: .orange))
            .disabled(!gameState.canUndo)
            .opacity(gameState.canUndo ? 1 : 0.35)
    }

    private var doneButton: some View {
        Button("Done") { gameState.commitMoves() }
            .buttonStyle(ActionButtonStyle(color: .green))
            .disabled(!gameState.canCommit)
            .opacity(gameState.canCommit ? 1 : 0.45)
    }

    private func newGameButton(primary: Bool) -> some View {
        Button("New Game") { gameState.newGame() }
            .buttonStyle(ActionButtonStyle(color: primary ? .blue : Color(white: 1.0, opacity: 0.15)))
    }

    // MARK: Tap handling

    private func handleTap(index: Int) {
        guard gameState.phase == .moving else { return }
        if gameState.inputMode == .checkerFirst {
            gameState.tapPoint(index)
        } else {
            gameState.selectDestinationWithDie(index)
        }
    }

    // MARK: Helpers

    private func triangleColor(index: Int) -> Color {
        index % 2 == 0
            ? Color(red: 0.78, green: 0.20, blue: 0.20)
            : Color(red: 0.90, green: 0.85, blue: 0.68)
    }

    private func qualityColor(_ q: MoveQuality) -> Color {
        switch q.colorName {
        case "green":  return .green
        case "mint":   return .mint
        case "blue":   return .blue
        case "yellow": return Color(red: 0.65, green: 0.65, blue: 0)
        case "orange": return .orange
        case "red":    return .red
        default:       return .gray
        }
    }

    private func pipCount(isWhite: Bool) -> Int {
        var pip = 0
        let b = gameState.board
        for i in 0..<24 {
            if isWhite && b.points[i] > 0 { pip += b.points[i] * (i + 1) }
            if !isWhite && b.points[i] < 0 { pip += (-b.points[i]) * (24 - i) }
        }
        if isWhite  { pip += b.whiteBar * 25 }
        else        { pip += b.blackBar * 25 }
        return pip
    }
}

// MARK: - Triangle shape

struct TriangleShape: Shape {
    let pointingDown: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointingDown {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Button style

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(color)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
    }
}

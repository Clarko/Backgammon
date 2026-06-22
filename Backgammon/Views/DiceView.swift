import SwiftUI

struct DiceFaceView: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: size * 0.15)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            pipLayout(for: value, size: size)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func pipLayout(for value: Int, size: CGFloat) -> some View {
        let pipSize = size * 0.18
        let pad = size * 0.22
        switch value {
        case 1:
            pip(pipSize).position(x: size/2, y: size/2)
        case 2:
            pip(pipSize).position(x: pad, y: pad)
            pip(pipSize).position(x: size-pad, y: size-pad)
        case 3:
            pip(pipSize).position(x: pad, y: pad)
            pip(pipSize).position(x: size/2, y: size/2)
            pip(pipSize).position(x: size-pad, y: size-pad)
        case 4:
            pip(pipSize).position(x: pad, y: pad)
            pip(pipSize).position(x: size-pad, y: pad)
            pip(pipSize).position(x: pad, y: size-pad)
            pip(pipSize).position(x: size-pad, y: size-pad)
        case 5:
            pip(pipSize).position(x: pad, y: pad)
            pip(pipSize).position(x: size-pad, y: pad)
            pip(pipSize).position(x: size/2, y: size/2)
            pip(pipSize).position(x: pad, y: size-pad)
            pip(pipSize).position(x: size-pad, y: size-pad)
        case 6:
            pip(pipSize).position(x: pad, y: pad)
            pip(pipSize).position(x: size-pad, y: pad)
            pip(pipSize).position(x: pad, y: size/2)
            pip(pipSize).position(x: size-pad, y: size/2)
            pip(pipSize).position(x: pad, y: size-pad)
            pip(pipSize).position(x: size-pad, y: size-pad)
        default:
            EmptyView()
        }
    }

    private func pip(_ size: CGFloat) -> some View {
        Circle().fill(Color.black).frame(width: size, height: size)
    }
}

struct DiceRowView: View {
    let dice: [Int]
    let usedDice: [Bool]
    let diceFirstMode: Bool
    let selectedDieIndex: Int?
    let onDieTap: ((Int) -> Void)?

    private let dieSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<dice.count, id: \.self) { i in
                let isUsed = i < usedDice.count && usedDice[i]
                let isSelected = selectedDieIndex == i
                ZStack {
                    if diceFirstMode && !isUsed {
                        RoundedRectangle(cornerRadius: dieSize * 0.15 + 3)
                            .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 3)
                            .frame(width: dieSize + 6, height: dieSize + 6)
                    }
                    DiceFaceView(value: dice[i], size: dieSize)
                        .opacity(isUsed ? 0.3 : 1.0)
                        .scaleEffect(isSelected ? 1.12 : 1.0)
                        .animation(.spring(response: 0.2), value: isSelected)
                }
                .onTapGesture {
                    if diceFirstMode && !isUsed { onDieTap?(i) }
                }
            }
        }
    }
}

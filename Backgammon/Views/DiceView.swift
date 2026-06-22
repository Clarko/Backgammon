// DiceView.swift
// Renders a single die face with pips.

import SwiftUI

struct DiceView: View {
    let value: Int
    var used: Bool = false

    private let pipPositions: [Int: [(CGFloat, CGFloat)]] = [
        1: [(0.5, 0.5)],
        2: [(0.25, 0.25), (0.75, 0.75)],
        3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
        4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
        5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
        6: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.5), (0.75, 0.5), (0.25, 0.75), (0.75, 0.75)]
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(used ? Color.gray.opacity(0.35) : Color.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)

            GeometryReader { geo in
                let size = geo.size
                ForEach(pipPositions[value] ?? [], id: \.0) { (x, y) in
                    Circle()
                        .fill(used ? Color.gray : Color.black)
                        .frame(width: size.width * 0.18, height: size.width * 0.18)
                        .position(x: size.width * x, y: size.height * y)
                }
            }
        }
        .frame(width: 40, height: 40)
        .opacity(used ? 0.4 : 1.0)
    }
}

struct DiceRowView: View {
    let dice: [Int]
    let usedDice: [Bool]
    var diceFirstMode: Bool = false
    var selectedDieIndex: Int? = nil
    var onDieTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(dice.indices, id: \.self) { i in
                let isUsed     = usedDice.indices.contains(i) && usedDice[i]
                let isSelected = selectedDieIndex == i

                ZStack {
                    if diceFirstMode && !isUsed {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 3)
                            .frame(width: 46, height: 46)
                    }
                    DiceView(value: dice[i], used: isUsed)
                        .scaleEffect(isSelected ? 1.10 : 1.0)
                        .animation(.spring(response: 0.2), value: isSelected)
                }
                .onTapGesture {
                    if diceFirstMode && !isUsed { onDieTap?(i) }
                }
            }
        }
    }
}

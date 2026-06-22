import SwiftUI

struct ContentView: View {
    @StateObject private var gameState = GameState()

    var body: some View {
        BoardView(gameState: gameState)
            .ignoresSafeArea()
    }
}

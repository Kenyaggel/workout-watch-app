import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Workout").font(.largeTitle).bold()
            Text("Manage your workouts from your Apple Watch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
}

#Preview {
    ContentView()
}

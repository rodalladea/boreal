import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView()
            .frame(width: 320, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}

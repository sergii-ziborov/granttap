import SwiftUI

struct ProjectRequiredView: View {
    @ObservedObject var model: DesktopModel
    let title: String
    let symbol: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.largeTitle.bold())
            DesktopCard {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: symbol)
                        .font(.system(size: 35))
                        .foregroundStyle(.orange)
                        .frame(width: 50)
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Choose a Project").font(.title2.bold())
                        Text(explanation).foregroundStyle(.secondary)
                        HStack {
                            Button("Open Mesh") { model.selected = .project }
                            Button("Connection") { model.selected = .engine }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI
import VocabKit

/// Which model server the studio is using, at a glance — and the way to change it.
struct ModelStatusButton: View {
    @ObservedObject var studio: GenerationStudio
    @Environment(\.colorScheme) private var scheme
    @State private var showingSettings = false

    var body: some View {
        Button {
            showingSettings.toggle()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 3)
                Text(title)
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(Color.primaryText(scheme))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 260)
        .help("The local model writing your cards")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            ModelSettingsView(studio: studio)
        }
        .accessibilityLabel("Model: \(title)")
    }

    private var title: String {
        switch studio.connection {
        case .unknown, .checking: return "Looking for a model…"
        case .connected(let server):
            return studio.endpoint.model.isEmpty ? server : "\(server) · \(Self.shortModelName(studio.endpoint.model))"
        case .unreachable: return "No model server"
        }
    }

    private var dotColor: Color {
        switch studio.connection {
        case .connected: return Palette.success
        case .unreachable: return Palette.amber
        case .unknown, .checking: return Palette.learning
        }
    }

    /// "lmstudio-community/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf" reads
    /// as "qwen2.5-7b-instruct-q4_k_m".
    static func shortModelName(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.hasSuffix(".gguf") ? String(last.dropLast(5)) : last
    }
}

/// Server address, model choice, and help for starting a server.
struct ModelSettingsView: View {
    @ObservedObject var studio: GenerationStudio
    @Environment(\.colorScheme) private var scheme
    @State private var address = ""
    @State private var addressError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local model")
                .font(.rounded(15, .bold))
                .foregroundStyle(Color.primaryText(scheme))

            VStack(alignment: .leading, spacing: 6) {
                Text("Server address")
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(Color.secondaryText(scheme))
                HStack(spacing: 8) {
                    TextField("http://127.0.0.1:1234/v1", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyAddress)
                    Button("Connect", action: applyAddress)
                        .disabled(studio.connection == .checking)
                }
                if addressError {
                    Text("That doesn't look like a server address. Try something like localhost:1234.")
                        .font(.rounded(11, .medium))
                        .foregroundStyle(Palette.amber)
                }
                statusLine
            }

            if !studio.availableModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.rounded(11, .semibold))
                        .foregroundStyle(Color.secondaryText(scheme))
                    Picker("Model", selection: $studio.endpoint.model) {
                        ForEach(studio.availableModels, id: \.self) { model in
                            Text(ModelStatusButton.shortModelName(model)).tag(model)
                        }
                    }
                    .labelsHidden()
                    .disabled(studio.isWorking)
                }
            }

            if studio.discoveredServers.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Also running on this Mac")
                        .font(.rounded(11, .semibold))
                        .foregroundStyle(Color.secondaryText(scheme))
                    ForEach(studio.discoveredServers.filter { $0.endpoint.baseURL != studio.endpoint.baseURL }) { server in
                        Button {
                            studio.choose(server)
                            address = server.endpoint.baseURL.absoluteString
                        } label: {
                            Label("\(server.name) — \(server.models.count) model\(server.models.count == 1 ? "" : "s")",
                                  systemImage: "server.rack")
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            if case .unreachable = studio.connection {
                Text(GenerationStudio.noServerHelp)
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { address = studio.endpoint.baseURL.absoluteString }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch studio.connection {
        case .checking, .unknown:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking for a server…")
            }
            .font(.rounded(11, .medium))
            .foregroundStyle(Color.secondaryText(scheme))
        case .connected(let server):
            Label("Connected to \(server)", systemImage: "checkmark.circle.fill")
                .font(.rounded(11, .semibold))
                .foregroundStyle(Palette.success)
        case .unreachable:
            Label("Nothing answered at \(GenerationStudio.address(of: studio.endpoint))",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.rounded(11, .semibold))
                .foregroundStyle(Palette.amber)
        }
    }

    private func applyAddress() {
        guard let url = LLMEndpoint.baseURL(from: address) else {
            addressError = true
            return
        }
        addressError = false
        address = url.absoluteString
        studio.endpoint = LLMEndpoint(baseURL: url, model: studio.endpoint.model)
        Task { await studio.connect(discovering: false) }
    }
}

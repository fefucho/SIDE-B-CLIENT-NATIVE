import SwiftUI

/// Hoja modal para mostrar el estado y progreso de actualización de Side B.
public struct UpdateModalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var updateService: UpdateService = UpdateService.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerView
            contentView
            footerView
        }
        .padding(24)
        .frame(width: 500)
        .background(Color.sidebDarkBackground)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 38))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.title3.bold())
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch updateService.state {
        case .idle, .checking:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Buscando nuevas versiones en GitHub…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)

        case .upToDate:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("Tienes la versión más reciente instalada (\(updateService.currentVersion)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)

        case .available(let info):
            VStack(alignment: .leading, spacing: 8) {
                Text("Notas de la versión:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(info.releaseNotes)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 160)
                .background(Color.sidebCardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sidebCardBorder, lineWidth: 0.5)
                )
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 10) {
                Text("Descargando actualización… (\(Int(progress * 100))%)")
                    .font(.callout.weight(.medium))

                ProgressView(value: progress)
                    .tint(Color.sidebAccent)

                Text("Por favor, espera mientras se descarga el nuevo paquete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)

        case .installing:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Instalando y reiniciando Side B automáticamente…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("No se pudo completar la comprobación o actualización:")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Spacer()
            switch updateService.state {
            case .idle, .checking:
                Button("Cancelar") {
                    updateService.isSheetPresented = false
                    dismiss()
                }

            case .upToDate, .failed:
                Button("Aceptar") {
                    updateService.isSheetPresented = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            case .available(let info):
                Button("Recordar más tarde") {
                    updateService.isSheetPresented = false
                    dismiss()
                }
                .disabled(updateService.state == .installing)

                Button("Actualizar ahora") {
                    Task {
                        await updateService.downloadAndInstall(release: info)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.sidebAccent)

            case .downloading:
                Button("Cancelar") {
                    updateService.isSheetPresented = false
                    dismiss()
                }

            case .installing:
                EmptyView()
            }
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch updateService.state {
        case .idle, .checking:
            return "arrow.triangle.2.circlepath.circle"
        case .upToDate:
            return "checkmark.circle.fill"
        case .available:
            return "arrow.down.circle.fill"
        case .downloading, .installing:
            return "arrow.down.app.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch updateService.state {
        case .idle, .checking, .available, .downloading, .installing:
            return Color.sidebAccent
        case .upToDate:
            return .green
        case .failed:
            return .red
        }
    }

    private var titleText: String {
        switch updateService.state {
        case .idle, .checking:
            return "Buscando actualizaciones"
        case .upToDate:
            return "Side B está al día"
        case .available(let info):
            return "Side B \(info.version) disponible"
        case .downloading:
            return "Descargando actualización"
        case .installing:
            return "Instalando versión"
        case .failed:
            return "Aviso de actualización"
        }
    }

    private var subtitleText: String {
        switch updateService.state {
        case .available(let info):
            return "Versión actual: \(updateService.currentVersion) → Nueva: \(info.version)"
        default:
            return "Versión actual \(updateService.currentVersion)"
        }
    }
}

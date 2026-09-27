import SwiftUI

/// Hoja modal estilo nativo Liquid Glass para mostrar el estado, Fix Report
/// y opciones de actualización de Side B.
public struct UpdateModalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var updateService: UpdateService = UpdateService.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerView
            contentView
            footerView
        }
        .padding(24)
        .frame(width: 540)
        .background(Color.sidebDarkBackground)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.title3.bold())

                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if case .available(let info) = updateService.state {
                    HStack(spacing: 8) {
                        versionBadge(label: "Instalada", version: updateService.currentVersion, isCurrent: true)
                        Image(systemName: "arrow.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        versionBadge(label: "Nueva", version: info.version, isCurrent: false)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func versionBadge(label: String, version: String, isCurrent: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(version)
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.sidebCardBackground : Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCurrent ? Color.sidebCardBorder : Color.white.opacity(0.3), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var contentView: some View {
        switch updateService.state {
        case .idle, .checking:
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text("Comprobando nuevas versiones en GitHub…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .upToDate:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.green)
                Text("Tienes la versión más reciente instalada (\(updateService.currentVersion)).")
                    .font(.callout.weight(.medium))
                Text("Side B está totalmente actualizado con las últimas mejoras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .available(let info):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.primary)
                    Text("Novedades y correcciones (Fix Report):")
                        .font(.callout.bold())
                }

                ScrollView {
                    Text(LocalizedStringKey(info.releaseNotes))
                        .font(.callout)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(height: 190)
                .background(Color.sidebCardBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.sidebCardBorder, lineWidth: 0.5)
                )
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Descargando actualización…")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(.primary)
                }

                ProgressView(value: progress)
                    .tint(.white)

                Text("Descargando paquete optimizado para Apple Silicon directamente de GitHub Releases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)

        case .installing:
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instalando actualización…")
                        .font(.callout.weight(.semibold))
                    Text("Side B se reiniciará automáticamente en unos segundos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text("No se pudo completar la comprobación o actualización:")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            switch updateService.state {
            case .idle, .checking:
                Spacer()
                Button("Cancelar") {
                    updateService.isSheetPresented = false
                    dismiss()
                }

            case .upToDate:
                Spacer()
                Button("Entendido") {
                    updateService.isSheetPresented = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            case .failed:
                Spacer()
                Button("Cerrar") {
                    updateService.isSheetPresented = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            case .available(let info):
                Button("Omitir esta versión") {
                    updateService.skipVersion(info.version)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
                .help("No volver a avisar automáticamente sobre la versión \(info.version)")

                Spacer()

                Button("Recordar más tarde") {
                    updateService.isSheetPresented = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Actualizar ahora") {
                    Task {
                        await updateService.downloadAndInstall(release: info)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .keyboardShortcut(.defaultAction)

            case .downloading:
                Spacer()
                Button("Cancelar descarga") {
                    updateService.isSheetPresented = false
                    dismiss()
                }

            case .installing:
                EmptyView()
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch updateService.state {
        case .idle, .checking:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle.fill"
        case .available:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.to.line.compact"
        case .installing:
            return "gearshape.arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch updateService.state {
        case .idle, .checking, .available, .downloading, .installing:
            return .white
        case .upToDate:
            return .green
        case .failed:
            return .red
        }
    }

    private var iconBackgroundColor: Color {
        iconColor
    }

    private var titleText: String {
        switch updateService.state {
        case .idle, .checking:
            return "Buscando actualizaciones"
        case .upToDate:
            return "Side B está al día"
        case .available(let info):
            return "Nueva versión disponible: Side B \(info.version)"
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
        case .available:
            return "Una versión más reciente de Side B está lista para descargar e instalar."
        case .upToDate:
            return "No hay nuevas actualizaciones en este momento."
        case .downloading:
            return "El paquete se está descargando de forma segura."
        case .installing:
            return "Reemplazando archivos y preparando el reinicio."
        case .failed:
            return "Hubo un inconveniente al comprobar las actualizaciones."
        default:
            return "Versión actual instalada: \(updateService.currentVersion)"
        }
    }
}

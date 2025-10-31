import SwiftUI

struct SpotDetailContextViewLoaded: View {
    let contextData: SpotContextData

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RestriccionesSection(items: contextData.restricciones)
                InfraestructurasSection(items: contextData.infraestructuras)
                MedioambienteSection(items: contextData.medioambiente)
                NotamsSection(items: contextData.notams)
                UrbanasSection(items: contextData.urbanas)

                // ⚠️ Aviso legal como contexto adicional
                VStack(alignment: .leading, spacing: 6) {
                    Text("⚠️ Aviso")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)

                    Text("La información de contexto aéreo puede no ser 100% precisa ni estar actualizada. Cada usuario es responsable de verificarla. SpotItFly no se hace responsable del uso que se haga de estos datos.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 1)
                )
                .cornerRadius(10)
                .shadow(color: Color.orange.opacity(0.15), radius: 2, x: 0, y: 1)
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
}


// MARK: - Secciones
private struct InfraestructurasSection: View {
    let items: [InfraestructuraFeature]
    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "Infraestructuras", color: .blue)
            ForEach(items, id: \.id) { item in
                ContextItem(
                    title: item.properties.identifier ?? "(Sin nombre)",
                    message: item.properties.message,
                    color: .blue
                )
            }
        }
    }
}

private struct RestriccionesSection: View {
    let items: [ENAIREFeature]
    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "Restricciones Aéreas", color: .orange)
            ForEach(items, id: \.id) { item in
                ContextItem(
                    title: item.displayName,
                    message: item.displayMessageHTML,
                    color: .orange
                )
            }
        }
    }
}

private struct UrbanasSection: View {
    let items: [ENAIREFeature]
    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "Zonas Urbanas", color: .purple)
            ForEach(items, id: \.id) { item in
                ContextItem(
                    title: "Zona Urbana",
                    message: item.displayMessageHTML,
                    color: .purple
                )
            }
        }
    }
}

private struct MedioambienteSection: View {
    let items: [ENAIREFeature]
    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "Medioambiente", color: .green)
            ForEach(items, id: \.id) { item in
                ContextItem(
                    title: "Zona Medioambiental",
                    message: item.displayMessageHTML,
                    color: .green
                )
            }
        }
    }
}

private struct NotamsSection: View {
    let items: [NOTAMFeature]
    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "NOTAMs", color: .red)
            ForEach(items, id: \.id) { item in
                NotamItemView(item: item)
            }
        }
    }
}

// MARK: - NOTAM Item
private struct NotamItemView: View {
    let item: NOTAMFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.attributes.notamId ?? "(Sin ID)")
                .font(.subheadline)
                .bold()
                .foregroundColor(.red)

            if let desde = item.attributes.itemBstr {
                NotamLine(icon: "📅", text: "DESDE: \(desde)")
            }

            if let hasta = item.attributes.itemCstr {
                NotamLine(icon: "📅", text: "HASTA: \(hasta)")
            }

            if let horario = item.attributes.itemD, !horario.isEmpty {
                NotamLine(icon: "⏰", text: "HORARIO: \(horario)")
            }

            if let descripcion = item.attributes.itemE, !descripcion.isEmpty {
                NotamLine(icon: "📝", text: "DESCRIPCIÓN: \(descripcion)")
            } else if let descripcion = item.attributes.DESCRIPTION, !descripcion.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("📝").font(.caption)
                    HTMLText(html: descripcion)
                        .foregroundColor(.primary) // 🔹 texto adaptativo
                        .background(Color.clear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.red.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Subvista para línea NOTAM
private struct NotamLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(icon).font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary) // 🔹 texto adaptativo
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Cabecera
private struct SectionHeader: View {
    let title: String
    let color: Color
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .cornerRadius(8)
    }
}

// MARK: - Tarjeta genérica
private struct ContextItem: View {
    let title: String
    let message: String?
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundColor(color)

            if let msg = message, !msg.isEmpty {
                HTMLText(html: msg)
                    .foregroundColor(.primary) // 🔹 texto adaptativo
                    .background(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: color.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

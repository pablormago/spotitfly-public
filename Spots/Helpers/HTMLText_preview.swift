import SwiftUI

struct HTMLText_Preview: View {
    private let sampleHTML = """
    Se encuentra en una zona geográficas de UAS <font color='#d2691e'> restringida al vuelo fotográfico.</font>
    <p>Más información en AIP apartado AIC <font color="#009fda">
    <a href='https://aip.enaire.es/AIP/contenido_AIC/N/Le_Circ_2020_N_05_es.pdf' target='_blank'>AIC NTL 05/20</a>
    </font>.</p>
    <p>Solicite los condicionantes técnicos al CECAF en el email:
    <a href="mailto:cecaf@ea.mde.es">cecaf@ea.mde.es</a></p>
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("🔍 Test de renderizado HTML")
                    .font(.headline)

                HTMLText(html: sampleHTML)
                    .frame(maxHeight: .infinity)
                    .padding()
                    .border(.blue)

                Text("👆 Arriba deberías ver el texto con colores, enlace clicable y email.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    HTMLText_Preview()
}

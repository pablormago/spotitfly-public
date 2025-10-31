import Foundation

struct SpotContextData {
    var infraestructuras: [InfraestructuraFeature] = []
    var restricciones: [ENAIREFeature] = []      // Aero
    var urbanas: [ENAIREFeature] = []            // Urbano
    var medioambiente: [ENAIREFeature] = []      // Medioambiente
    var notams: [NOTAMFeature] = []
}

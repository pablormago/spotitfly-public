//
//  CommunityGuidelinesView.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


import SwiftUI

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Normas de la comunidad")
                    .font(.title.bold())

                Text("""
Estas normas te ayudan a usar Spots con respeto y seguridad. Al usar la app, aceptas cumplirlas.

**No permitido**
• Spam o promoción engañosa  
• Insultos, acoso, amenazas o incitación al odio  
• Contenido sexualmente explícito o violento  
• Información falsa que pueda causar daño (ubicación errónea, accesos peligrosos, etc.)  
• Revelar datos personales de terceros sin permiso  
• Publicar material con derechos de autor sin autorización

**Spots y descripciones**
• Verifica la ubicación, accesos y restricciones antes de publicar  
• Indica riesgos y limitaciones cuando existan  
• No subas imágenes de otras personas sin su consentimiento

**Comentarios y chat**
• Debate con respeto, sin ataques personales  
• Reporta contenido inadecuado: mantén la comunidad limpia

**Seguridad**
• Respeta la normativa local (zonas restringidas, NOTAM, parques, etc.)  
• Evita poner en peligro a personas, fauna o patrimonio

**Moderación**
Los reportes pueden derivar en edición o eliminación de contenido y/o suspensión de cuentas.
""")
                .font(.body)
                .foregroundColor(.primary)

                Text("¿Ves algo que incumple estas normas? Usa el botón **Reportar**.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Normas de la comunidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

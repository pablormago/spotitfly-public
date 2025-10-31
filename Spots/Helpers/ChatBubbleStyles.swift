// BEGIN FILE ChatBubbleStyles.swift
import SwiftUI

public enum GroupRole {
    case solo, top, middle, bottom
}

public struct GroupedBubbleShape: Shape {
    public let isMine: Bool
    public let role: GroupRole
    public let radius: CGFloat

    public init(isMine: Bool, role: GroupRole, radius: CGFloat = 20) {
        self.isMine = isMine
        self.role = role   // 👈 fix: asignación correcta a la propiedad
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        var tl = radius, tr = radius, bl = radius, br = radius

        // Aplana las esquinas del "lado avatar":
        //  - Entrantes (izquierda): aplanar IZQ (tl/bl)
        //  - Salientes (derecha):  aplanar DCHA (tr/br)
        // BEGIN REPLACE — aplanado más marcado
        func flatten(_ top: inout CGFloat, _ bottom: inout CGFloat) {
            switch role {
            case .solo:
                break
            case .top:
                bottom = 10
            case .middle:
                top = 8; bottom = 8
            case .bottom:
                top = 10
            }
        }
        // END REPLACE — aplanado más marcado



        if isMine {
            // Mis mensajes van a la derecha → aplanar lado derecho
            flatten(&tr, &br)
        } else {
            // Entrantes a la izquierda → aplanar lado izquierdo
            flatten(&tl, &bl)
        }

        var path = Path()
        path.addRoundedRect(in: rect,
                            topLeftRadius: tl, topRightRadius: tr,
                            bottomLeftRadius: bl, bottomRightRadius: br)
        return path
    }
}

private extension Path {
    mutating func addRoundedRect(in rect: CGRect,
                                 topLeftRadius tl: CGFloat,
                                 topRightRadius tr: CGFloat,
                                 bottomLeftRadius bl: CGFloat,
                                 bottomRightRadius br: CGFloat) {
        let tlr = max(0, min(min(rect.width, rect.height)/2, tl))
        let trr = max(0, min(min(rect.width, rect.height)/2, tr))
        let blr = max(0, min(min(rect.width, rect.height)/2, bl))
        let brr = max(0, min(min(rect.width, rect.height)/2, br))

        move(to: CGPoint(x: rect.minX + tlr, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - trr, y: rect.minY))
        addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + trr), control: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - brr))
        addQuadCurve(to: CGPoint(x: rect.maxX - brr, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX + blr, y: rect.maxY))
        addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - blr), control: CGPoint(x: rect.minX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + tlr))
        addQuadCurve(to: CGPoint(x: rect.minX + tlr, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        closeSubpath()
    }
}
// END FILE ChatBubbleStyles.swift

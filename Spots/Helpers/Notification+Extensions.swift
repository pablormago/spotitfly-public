//
//  Notification+Extensions.swift
//  Spots
//
//  Created by Pablo Jimenez on 23/9/25.
//

import Foundation

extension Notification.Name {
    /// Se lanza cuando cambian los comentarios (añadir, editar o borrar)
    //static let commentsDidChange = Notification.Name("commentsDidChange")

    /// Se lanza cuando el usuario entra en un Spot desde la campanita y se marca como visto
    static let spotSeen = Notification.Name("spotSeen")
}


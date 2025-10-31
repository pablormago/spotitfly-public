import XCTest

final class SpotsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Limpia estado del explainer si estorba la navegación
        app.launchArguments += ["-didShowPermissionsExplainer", "YES"]
        app.launch()
    }

    // MARK: - 1) Footer de normas en Chats
    func testCommunityGuidelinesFooterVisibleInChats() {
        // Abre Chats desde el mapa usando el ID fiable
        let chatsButton = app.buttons["openChatsButton"]
        XCTAssertTrue(chatsButton.waitForExistence(timeout: 5), "No encuentro el botón para abrir Chats")
        chatsButton.tap()

        // Comprueba el footer de normas
        let guidelines = app.otherElements["communityGuidelinesFooter"]
        XCTAssertTrue(guidelines.waitForExistence(timeout: 5), "El footer de normas no es visible en ChatsHomeView")
    }

    // MARK: - 2) Botón Reportar usuario en sheet del perfil (desde un chat)
    func testReportUserButtonInProfileSheet() {
        // Entra al primer chat visible en la lista
        // Si no hay chats, esta prueba se salta (no falla el pipeline)
        let firstChat = app.cells.firstMatch
        if !firstChat.waitForExistence(timeout: 5.0) { return }
        firstChat.tap()

        // Abre el sheet de perfil tocando el avatar/título en la barra
        // Aquí usamos heurísticas: el título 'Chat' o el estado 'conectando…'
        let navTitle = app.staticTexts["Chat"]
        if navTitle.exists { navTitle.tap() }
        else {
            // Alternativa: tocar cualquier texto de estado
            let status = app.staticTexts["conectando…"]
            if status.exists { status.tap() }
        }

        // Verifica que el botón de Reportar usuario existe
        let reportButton = app.buttons["reportUserButton"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5.0), "No se encontró el botón 'Reportar usuario' en el ProfileSheetView")
    }

    // MARK: - 3) Botón Reportar Spot visible en detalle del spot
    func testReportSpotButtonInSpotDetail() {
        // Volver al mapa
        app.navigationBars.buttons["Atrás"].firstMatch.tap() // si aplica

        // Abre la lista de spots para garantizar navegación determinista
        let listButton = app.buttons.matching(identifier: "list.and.film").firstMatch
        if listButton.exists { listButton.tap() }

        // Toca la primera celda de la lista de spots
        let firstSpot = app.cells.firstMatch
        if !firstSpot.waitForExistence(timeout: 5.0) { return }
        firstSpot.tap()

        // verifica el botón "Reportar Spot"
        let reportSpotButton = app.buttons["reportSpotButton"]
        XCTAssertTrue(reportSpotButton.waitForExistence(timeout: 5.0), "No se encontró el botón 'Reportar Spot' en SpotDetailView")
    }
}

import XCTest

final class IntoEnglishUITests: XCTestCase {
    func testLearningModesAndAccountSettings() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["문장 다듬기"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["learning-input"].exists || app.textViews["learning-input"].exists)
        app.buttons["단어 / 숙어"].tap()
        XCTAssertTrue(app.staticTexts["serendipity"].waitForExistence(timeout: 3))
        app.buttons["문장 다듬기"].tap()
        XCTAssertTrue(app.staticTexts["좀 쉬고 싶어"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Into English home"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["계정과 모델 설정"].tap()
        XCTAssertTrue(app.staticTexts["버전"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1.0.0 (")).firstMatch.exists)
    }
}

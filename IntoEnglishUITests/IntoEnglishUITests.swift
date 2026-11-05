import XCTest

final class IntoEnglishUITests: XCTestCase {
    func testLearningModesAndAccountSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["문장 다듬기"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["learning-input"].exists || app.textViews["learning-input"].exists)
        app.buttons["단어 / 숙어"].tap()
        XCTAssertTrue(app.buttons["example-0"].waitForExistence(timeout: 3))
        app.buttons["문장 다듬기"].tap()
        XCTAssertTrue(app.buttons["example-0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mood-casual"].exists)
        app.buttons["tone-toggle"].tap()
        let tones = ["casual", "polite", "formal"].map { app.buttons["mood-\($0)"] }
        for tone in tones { XCTAssertTrue(tone.isHittable) }
        XCTAssertLessThan(abs(tones[0].frame.midY - tones[2].frame.midY), 2)
        app.buttons["mood-polite"].tap()
        XCTAssertFalse(app.buttons["mood-polite"].exists)
        XCTAssertTrue(app.buttons["tone-toggle"].label.contains("공손하게"))
        XCTAssertFalse(app.staticTexts["작은 연습, 더 자연스러운 영어."].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Into English home"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["사용량"].exists)
        app.buttons["계정과 모델 설정"].tap()
        XCTAssertTrue(app.staticTexts["버전"].waitForExistence(timeout: 3))
        app.buttons["english-region"].tap()
        app.buttons["영국"].tap()
        app.buttons["AI에 보내는 프롬프트"].tap()
        XCTAssertTrue(app.staticTexts["전송 프롬프트"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Use British English")).firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1.0.0 (")).firstMatch.exists)
    }
    func testSignedInSettingsUseFixedAIAndNativeDisconnectAlert() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-signed-in"]
        app.launch()
        app.buttons["계정과 모델 설정"].tap()
        XCTAssertTrue(app.staticTexts["test@example.invalid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["chatgpt-account-icon"].exists)
        XCTAssertTrue(app.staticTexts["GPT-6.1 Sol"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Light")).firstMatch.exists)
        XCTAssertFalse(app.buttons["사용량"].exists)
        XCTAssertFalse(app.buttons["사용할 모델"].exists)
        app.buttons["이 기기에서 계정 연결 해제"].tap()
        let alert = app.alerts["이 기기의 계정 연결을 해제할까요?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["취소"].tap()
        XCTAssertTrue(app.staticTexts["test@example.invalid"].exists)
    }

}

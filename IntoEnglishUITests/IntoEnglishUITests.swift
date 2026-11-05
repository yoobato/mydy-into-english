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
        app.buttons["사용량"].tap()
        XCTAssertTrue(app.staticTexts["이 계정의 전체 남은 한도"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ChatGPT 전체 사용량 확인"].exists)
        app.buttons["닫기"].tap()
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
}

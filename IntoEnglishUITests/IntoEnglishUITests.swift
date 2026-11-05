import XCTest

final class IntoEnglishUITests: XCTestCase {
    func testLearningModesAndAccountSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["문장 다듬기"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["learning-input"].exists || app.textViews["learning-input"].exists)
        let wordTab = app.buttons["mode-word"]
        let sentenceTab = app.buttons["mode-sentence"]
        XCTAssertEqual(wordTab.label, "단어")
        XCTAssertFalse(app.buttons["단어 / 숙어"].exists)
        // Exercise the held-down state and switching in both directions.
        wordTab.press(forDuration: 0.6)
        XCTAssertTrue(wordTab.isSelected)
        XCTAssertTrue(wordTab.isHittable)
        XCTAssertTrue(sentenceTab.isHittable)
        sentenceTab.press(forDuration: 0.6)
        XCTAssertTrue(sentenceTab.isSelected)
        wordTab.tap()
        XCTAssertTrue(wordTab.isSelected)
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
    func testSignedInSettingsSelectAIAndShowInlineDisconnectAlert() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-signed-in"]
        app.launch()
        app.buttons["계정과 모델 설정"].tap()
        XCTAssertTrue(app.staticTexts["test@example.invalid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["chatgpt-account-icon"].exists)
        XCTAssertTrue(app.buttons["ai-model"].exists)
        XCTAssertTrue(app.buttons["ai-reasoning"].exists)
        app.buttons["ai-model"].tap()
        let sol = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "GPT-6.1 Sol")).firstMatch
        XCTAssertTrue(sol.waitForExistence(timeout: 3))
        XCTAssertTrue(sol.label.contains("(추천)"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Model recommendation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["GPT-6 Astra"].label.contains("(추천)"))
        app.buttons["GPT-6 Astra"].tap()
        XCTAssertTrue(app.buttons["ai-model"].label.contains("Astra"))
        app.buttons["ai-reasoning"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Light")).firstMatch.label.contains("(추천)"))
        app.buttons["High"].tap()
        XCTAssertTrue(app.buttons["ai-reasoning"].label.contains("High"))
        XCTAssertFalse(app.buttons["사용량"].exists)
        let disconnect = app.buttons["account-disconnect"]
        let email = app.staticTexts["test@example.invalid"]
        XCTAssertLessThan(abs(disconnect.frame.midY - email.frame.midY), 10)
        XCTAssertGreaterThan(disconnect.frame.midX, email.frame.midX)
        disconnect.tap()
        let alert = app.alerts["이 기기의 계정 연결을 해제할까요?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["취소"].tap()
        XCTAssertTrue(app.staticTexts["test@example.invalid"].exists)
    }

}

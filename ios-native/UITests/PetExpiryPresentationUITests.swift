import XCTest

final class PetExpiryPresentationUITests: XCTestCase {
    func testUnsetExpiryHasNoFallbackDateAndCanSelectToday() throws {
        let app = launchPreview()
        let expiryTitle = app.buttons["编辑保质期"]
        scrollUntilHittable(expiryTitle, in: app)
        XCTAssertTrue(expiryTitle.waitForExistence(timeout: 5))
        expiryTitle.tap()

        let unsetDate = app.buttons["选择日期"]
        XCTAssertTrue(unsetDate.waitForExistence(timeout: 5))
        XCTAssertEqual(app.datePickers.count, 0, "an unset date must show a separate entry button without today's date underneath")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Unset expiry in the native editor"
        attachment.lifetime = .keepAlways
        add(attachment)

        unsetDate.tap()
        XCTAssertTrue(app.buttons["保质期设为今天"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["选择日期"].exists, "the placeholder and native date control must never render together")
        app.buttons["保存"].tap()
        let unsetBalance = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "未设置")).firstMatch
        XCTAssertTrue(unsetBalance.waitForExistence(timeout: 5), "opening the picker and saving without a choice must leave the balance undated")

        expiryTitle.tap()
        app.buttons["选择日期"].tap()
        app.buttons["保质期设为今天"].tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(unsetBalance.waitForExistence(timeout: 5), "cancel must discard the selected date draft")

        expiryTitle.tap()
        app.buttons["选择日期"].tap()
        app.buttons["保质期设为今天"].tap()
        app.buttons["保存"].tap()

        let savedBalance = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "4袋")).firstMatch
        XCTAssertTrue(savedBalance.waitForExistence(timeout: 5), "explicitly selecting today should save the existing four-bag balance")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "未设置")).firstMatch.exists)

        savedBalance.tap()
        XCTAssertTrue(app.buttons["清除日期"].waitForExistence(timeout: 5))
        app.buttons["清除日期"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(unsetBalance.waitForExistence(timeout: 5), "clearing and saving returns the balance to its unset state")
    }

    func testMultipleExpiryGroupsExpandAndDateRowsOpenTheEditor() throws {
        let app = launchPreview(multipleGroups: true)
        let expiryTitle = app.buttons["编辑保质期"]
        scrollUntilHittable(expiryTitle, in: app)
        XCTAssertTrue(expiryTitle.waitForExistence(timeout: 5))

        let firstDate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2027.03.01")).firstMatch
        XCTAssertTrue(firstDate.waitForExistence(timeout: 5), "the collapsed card shows its nearest expiry")
        XCTAssertTrue(app.buttons["展开保质期日期，2条"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2027.08.08")).firstMatch.exists)
        let collapsedCard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsedCard.name = "Collapsed expiry summary"
        collapsedCard.lifetime = .keepAlways
        add(collapsedCard)

        app.buttons["展开保质期日期，2条"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2027.08.08")).firstMatch.waitForExistence(timeout: 5))
        let expandedCard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedCard.name = "Expanded expiry rows"
        expandedCard.lifetime = .keepAlways
        add(expandedCard)
        app.buttons["收起保质期日期"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2027.08.08")).firstMatch.exists)

        firstDate.tap()
        XCTAssertTrue(app.navigationBars["编辑保质期"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(expiryTitle.waitForExistence(timeout: 5))
    }

    func testProductRowsFitLongFlavorAndKeepDatesOnTheirOwnLine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-codex-pet-list-ui-preview"]
        app.launch()

        let thumbnail = app.buttons["pet-product-thumbnail-preview-pet-food-long-flavor"]
        for _ in 0..<8 {
            if thumbnail.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        XCTAssertEqual(thumbnail.frame.width.rounded(), 64, "all product rows use the same 64-point thumbnail width")
        XCTAssertEqual(thumbnail.frame.height.rounded(), 64, "the thumbnail fills the three-line row height without growing into a poster")

        let undatedRow = app.buttons["pet-product-row-content-preview-pet-food-long-flavor"]
        XCTAssertTrue(undatedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(undatedRow.label.contains("鸡肉三文鱼蔓越莓"))
        XCTAssertTrue(undatedRow.label.contains("未评分"))
        XCTAssertTrue(undatedRow.label.contains("185g × 2罐"))
        XCTAssertFalse(undatedRow.label.contains("保质期"), "an undated product has no placeholder expiry line")

        let datedRow = app.buttons["pet-product-row-content-preview-pet-food-2"]
        XCTAssertTrue(datedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(datedRow.label.contains("保质期 2027.03.01"), "a product with a dated balance keeps the third expiry line")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "64 point pet product rows"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchPreview(multipleGroups: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-codex-expiry-ui-preview"]
        if multipleGroups {
            app.launchArguments.append("-codex-expiry-ui-preview-multiple")
        }
        app.launch()
        return app
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
}

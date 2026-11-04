import XCTest
@testable import ZMKKeymapViewerApp

/// Checking a zmk-config for the live layer and ZMK Studio
class FirmwareSetupTests: XCTestCase {

    private let westBefore = """
    manifest:
      remotes:
        - name: zmkfirmware
          url-base: https://github.com/zmkfirmware
      projects:
        - name: zmk
          remote: zmkfirmware
          revision: v0.2
          import: app/west.yml
      self:
        path: config
    """

    private let westAfter = """
    manifest:
      remotes:
        - name: zmkfirmware
          url-base: https://github.com/zmkfirmware
        - name: zzeneg
          url-base: https://github.com/zzeneg
        - name: srwi
          url-base: https://github.com/srwi
      projects:
        - name: zmk
          remote: zmkfirmware
          revision: v0.2
          import: app/west.yml
        # Raw HID transport (USB + BLE)
        - name: zmk-raw-hid
          remote: zzeneg
          revision: main
        - name: zmk-keypeek-layer-notifier
          remote: srwi
          revision: master
      self:
        path: config
    """

    /// With the commented-out example GitHub puts at the top of build.yaml
    private func build(shield: String, studio: Bool = true) -> String {
        """
        # include:
        #   - board: nice_nano_v2
        #     shield: corne_left
        #     snippet: studio-rpc-usb-uart
        ---
        include:
          - board: nice_nano_v2
            shield: \(shield)
        \(studio ? "    snippet: studio-rpc-usb-uart\n    cmake-args: -DCONFIG_ZMK_STUDIO=y" : "")
          - board: nice_nano_v2
            shield: cradio_right
        """
    }

    private let keymap = (name: "cradio.keymap", content: "&sys_reset &bootloader &studio_unlock")

    func testSweepBeforeTheLiveLayer() {
        let setup = FirmwareSetup.check(west: westBefore, build: build(shield: "cradio_left"), keymaps: [keymap])

        XCTAssertFalse(setup.hasModules)
        XCTAssertFalse(setup.hasRawHID)
        XCTAssertTrue(setup.hasStudio)
        XCTAssertTrue(setup.hasUnlockKey)
        XCTAssertFalse(setup.filesAreReady)
    }

    func testSweepWithTheLiveLayer() {
        let setup = FirmwareSetup.check(west: westAfter, build: build(shield: "cradio_left raw_hid_adapter"), keymaps: [keymap])

        XCTAssertTrue(setup.filesAreReady)
    }

    func testExamplesFitTheKeyboard() {
        let setup = FirmwareSetup.check(west: westBefore, build: build(shield: "cradio_left"), keymaps: [keymap])

        XCTAssertEqual(setup.board, "nice_nano_v2")
        XCTAssertEqual(setup.centralShield, "cradio_left")
        XCTAssertEqual(setup.keymapFile, "config/cradio.keymap")
    }

    func testCentralHalfWithoutStudioIsTheLeftOne() {
        let setup = FirmwareSetup.check(west: westAfter, build: build(shield: "corne_left", studio: false), keymaps: [])

        XCTAssertEqual(setup.centralShield, "corne_left")
        XCTAssertFalse(setup.hasStudio)
        XCTAssertFalse(setup.hasUnlockKey)
    }

    func testCommentedOutLinesDontCount() {
        let west = westBefore + "\n    # - name: zmk-raw-hid\n    # - name: zmk-keypeek-layer-notifier"
        let keymaps = [(name: "cradio.keymap", content: "// &studio_unlock\n&kp Q")]

        let setup = FirmwareSetup.check(west: west, build: build(shield: "cradio_left"), keymaps: keymaps)

        XCTAssertFalse(setup.hasModules)
        XCTAssertFalse(setup.hasUnlockKey)
    }

    func testEmptyFolderNeedsEverything() {
        let setup = FirmwareSetup.check(west: "", build: "", keymaps: [])

        XCTAssertEqual(setup, FirmwareSetup())
    }

    func testFindsTheRootFromTheConfigFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try build(shield: "cradio_left raw_hid_adapter").write(to: root.appendingPathComponent("build.yaml"), atomically: true, encoding: .utf8)
        try westAfter.write(to: config.appendingPathComponent("west.yml"), atomically: true, encoding: .utf8)
        try keymap.content.write(to: config.appendingPathComponent("cradio.keymap"), atomically: true, encoding: .utf8)

        XCTAssertEqual(FirmwareSetup.configRoot(for: config).standardizedFileURL, root.standardizedFileURL)
        XCTAssertTrue(FirmwareSetup.check(config).filesAreReady)
        XCTAssertTrue(FirmwareSetup.check(root).filesAreReady)
    }
}

import XCTest
@testable import ZMKKeymapViewerApp

/// Edits to a zmk-config: offered only when they are safe
class FirmwareEditsTests: XCTestCase {

    // The Sweep's files before the live layer
    private let sweepWest = """
    manifest:
      defaults:
        revision: v0.2
      remotes:
        - name: zmkfirmware
          url-base: https://github.com/zmkfirmware
        # Additional modules containing boards/shields/custom code can be listed here as well
        # See https://docs.zephyrproject.org/3.2.0/develop/west/manifest.html#projects
      projects:
        - name: zmk
          remote: zmkfirmware
          revision: v0.2
          import: app/west.yml
      self:
        path: config
    """

    private let sweepBuild = """
    # This file generates the GitHub Actions matrix.
    # include:
    #   - board: nice_nano_v2
    #     shield: corne_left
    #     snippet: studio-rpc-usb-uart
    #
    ---
    include:
      - board: nice_nano_v2
        shield: cradio_left
        snippet: studio-rpc-usb-uart
        cmake-args: -DCONFIG_ZMK_STUDIO=y
        artifact-name: cradio_left_with_studio
      - board: nice_nano_v2
        shield: cradio_right
    #  - board: nice_nano_v2
    #    shield: settings_reset
    """

    private func edit(_ proposal: ConfigEditProposal, file: StaticString = #filePath, line: UInt = #line) -> ConfigEdit? {
        guard case let .edit(edit) = proposal else {
            XCTFail("expected an edit, got \(proposal)", file: file, line: line)
            return nil
        }
        return edit
    }

    /// Lines of `after` that are not in `before`
    private func added(_ edit: ConfigEdit) -> [String] {
        var before = edit.before.components(separatedBy: "\n")
        return edit.after.components(separatedBy: "\n").filter { line in
            if let index = before.firstIndex(of: line) {
                before.remove(at: index)
                return false
            }
            return true
        }
    }

    // MARK: - west.yml

    func testAddsModulesToTheSweep() throws {
        let edit = try XCTUnwrap(edit(FirmwareEdits.addModules(toWest: sweepWest)))

        XCTAssertEqual(edit.file, "config/west.yml")
        XCTAssertEqual(edit.after, """
        manifest:
          defaults:
            revision: v0.2
          remotes:
            - name: zmkfirmware
              url-base: https://github.com/zmkfirmware
            - name: zzeneg
              url-base: https://github.com/zzeneg
            - name: srwi
              url-base: https://github.com/srwi
            # Additional modules containing boards/shields/custom code can be listed here as well
            # See https://docs.zephyrproject.org/3.2.0/develop/west/manifest.html#projects
          projects:
            - name: zmk
              remote: zmkfirmware
              revision: v0.2
              import: app/west.yml
            - name: zmk-raw-hid
              remote: zzeneg
              revision: main
            - name: zmk-keypeek-layer-notifier
              remote: srwi
              revision: master
          self:
            path: config
        """)
        XCTAssertTrue(FirmwareSetup.check(west: edit.after, build: "", keymaps: []).hasModules)
    }

    func testModulesOnlyOnce() throws {
        let edit = try XCTUnwrap(edit(FirmwareEdits.addModules(toWest: sweepWest)))

        XCTAssertEqual(FirmwareEdits.addModules(toWest: edit.after), .notNeeded)
    }

    func testReusesARemoteForTheSameAccount() throws {
        let west = sweepWest.replacingOccurrences(of: """
              url-base: https://github.com/zmkfirmware
        """, with: """
              url-base: https://github.com/zmkfirmware
            - name: keypeek
              url-base: https://github.com/srwi/
        """)

        let edit = try XCTUnwrap(edit(FirmwareEdits.addModules(toWest: west)))

        XCTAssertEqual(added(edit), [
            "    - name: zzeneg",
            "      url-base: https://github.com/zzeneg",
            "    - name: zmk-raw-hid",
            "      remote: zzeneg",
            "      revision: main",
            "    - name: zmk-keypeek-layer-notifier",
            "      remote: keypeek",
            "      revision: master",
        ])
    }

    func testFollowsTheFilesIndentation() throws {
        let west = """
        manifest:
          remotes:
          - name: zmkfirmware
            url-base: https://github.com/zmkfirmware
          projects:
          - name: zmk
            remote: zmkfirmware
            import: app/west.yml
        """

        let edit = try XCTUnwrap(edit(FirmwareEdits.addModules(toWest: west)))

        XCTAssertTrue(added(edit).contains("  - name: srwi"))
        XCTAssertTrue(added(edit).contains("    url-base: https://github.com/srwi"))
    }

    func testRemoteNameTakenElsewhereIsLeftToTheUser() {
        let west = sweepWest.replacingOccurrences(of: "- name: zmkfirmware", with: "- name: srwi")

        guard case .manual = FirmwareEdits.addModules(toWest: west) else { return XCTFail("expected manual") }
    }

    func testAnchorsAreLeftToTheUser() {
        let west = sweepWest.replacingOccurrences(of: "revision: v0.2\n  remotes:", with: "revision: &zmk v0.2\n  remotes:")

        guard case .manual = FirmwareEdits.addModules(toWest: west) else { return XCTFail("expected manual") }
    }

    // MARK: - build.yaml

    func testAddsRawHIDToTheSweepsCentralHalf() throws {
        let edit = try XCTUnwrap(edit(FirmwareEdits.enableRawHIDAndStudio(inBuild: sweepBuild)))

        XCTAssertEqual(edit.after, sweepBuild.replacingOccurrences(
            of: "shield: cradio_left\n", with: "shield: cradio_left raw_hid_adapter\n"
        ))
        XCTAssertEqual(FirmwareEdits.enableRawHIDAndStudio(inBuild: edit.after), .notNeeded)
    }

    func testKeepsNiceViewAndComments() throws {
        let build = """
        include:
          - board: nice_nano_v2
            shield: "corne_left nice_view_adapter nice_view" # with display
            cmake-args: -DCONFIG_ZMK_SLEEP=y
          - board: nice_nano_v2
            shield: corne_right nice_view_adapter nice_view
        """

        let edit = try XCTUnwrap(edit(FirmwareEdits.enableRawHIDAndStudio(inBuild: build, central: 0)))

        XCTAssertEqual(edit.after, """
        include:
          - board: nice_nano_v2
            shield: "corne_left nice_view_adapter nice_view raw_hid_adapter" # with display
            cmake-args: -DCONFIG_ZMK_SLEEP=y -DCONFIG_ZMK_STUDIO=y
            snippet: studio-rpc-usb-uart
          - board: nice_nano_v2
            shield: corne_right nice_view_adapter nice_view
        """)
    }

    func testUnclearCentralHalfIsAskedFor() {
        let build = """
        include:
          - board: nice_nano_v2
            shield: corne_dongle
          - board: nice_nano_v2
            shield: corne_left
          - board: nice_nano_v2
            shield: corne_right
        """

        XCTAssertEqual(
            FirmwareEdits.enableRawHIDAndStudio(inBuild: build),
            .chooseCentral(["nice_nano_v2 · corne_dongle", "nice_nano_v2 · corne_left", "nice_nano_v2 · corne_right"])
        )
    }

    func testBoardWithoutShieldGetsOne() throws {
        let build = """
        include:
          - board: glove80_lh
          - board: glove80_rh
        """

        let edit = try XCTUnwrap(edit(FirmwareEdits.enableRawHIDAndStudio(inBuild: build, central: 0)))

        XCTAssertEqual(edit.after, """
        include:
          - board: glove80_lh
            shield: raw_hid_adapter
            snippet: studio-rpc-usb-uart
            cmake-args: -DCONFIG_ZMK_STUDIO=y
          - board: glove80_rh
        """)
    }

    func testSingleEntryIsTheCentralHalf() throws {
        let build = """
        include:
          - board: nice_nano_v2
            shield: reviung41
        """

        let edit = try XCTUnwrap(edit(FirmwareEdits.enableRawHIDAndStudio(inBuild: build)))

        XCTAssertTrue(edit.after.contains("shield: reviung41 raw_hid_adapter"))
    }

    func testMatrixStyleIsLeftToTheUser() {
        let build = """
        board: [ "nice_nano_v2" ]
        shield: [ "corne_left", "corne_right" ]
        """

        guard case .manual = FirmwareEdits.enableRawHIDAndStudio(inBuild: build) else { return XCTFail("expected manual") }
    }

    func testAnotherSnippetIsLeftToTheUser() {
        let build = """
        include:
          - board: nice_nano_v2
            shield: corne_left
            snippet: zmk-usb-logging
        """

        guard case .manual = FirmwareEdits.enableRawHIDAndStudio(inBuild: build) else { return XCTFail("expected manual") }
    }

    func testInlineEntriesAreLeftToTheUser() {
        let build = """
        include:
          - { board: nice_nano_v2, shield: corne_left }
        """

        guard case .manual = FirmwareEdits.enableRawHIDAndStudio(inBuild: build) else { return XCTFail("expected manual") }
    }

    // MARK: - Writing

    func testWritesOnlyIfTheFileIsUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("build.yaml")
        try sweepBuild.write(to: url, atomically: true, encoding: .utf8)
        let edit = try XCTUnwrap(edit(FirmwareEdits.enableRawHIDAndStudio(inBuild: sweepBuild)))

        try "# edited meanwhile\n".appending(sweepBuild).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FirmwareEdits.apply(edit, in: root)) { error in
            XCTAssertEqual(error as? FirmwareEdits.ApplyError, .fileChanged)
        }

        try sweepBuild.write(to: url, atomically: true, encoding: .utf8)
        try FirmwareEdits.apply(edit, in: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), edit.after)
    }
}

/// What the firmware guide shows before the user agrees to an edit
class EditExcerptTests: XCTestCase {

    func testShowsTheChangedLineWithContext() {
        let edit = ConfigEdit(
            file: "build.yaml",
            before: "include:\n  - board: nice_nano_v2\n    shield: cradio_left\n    snippet: studio-rpc-usb-uart\n  - board: nice_nano_v2\n    shield: cradio_right",
            after: "include:\n  - board: nice_nano_v2\n    shield: cradio_left raw_hid_adapter\n    snippet: studio-rpc-usb-uart\n  - board: nice_nano_v2\n    shield: cradio_right"
        )

        let excerpts = EditExcerpt.excerpts(of: edit)

        XCTAssertEqual(excerpts.count, 1)
        XCTAssertEqual(excerpts[0].before.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(excerpts[0].before.filter(\.changed).map(\.text), ["    shield: cradio_left"])
        XCTAssertEqual(excerpts[0].after.filter(\.changed).map(\.text), ["    shield: cradio_left raw_hid_adapter"])
    }

    func testSeparateRegionsStaySeparate() {
        let lines = (1...20).map { "line \($0)" }
        var changed = lines
        changed.insert("new A", at: 2)
        changed.insert("new B", at: 18)

        let excerpts = EditExcerpt.excerpts(of: ConfigEdit(file: "x", before: lines.joined(separator: "\n"), after: changed.joined(separator: "\n")))

        XCTAssertEqual(excerpts.count, 2)
        XCTAssertEqual(excerpts[0].after.filter(\.changed).map(\.number), [3])
        XCTAssertEqual(excerpts[1].after.filter(\.changed).map(\.number), [19])
        XCTAssertTrue(excerpts.allSatisfy { $0.before.allSatisfy { !$0.changed } })
    }
}

import XCTest
@testable import SelectTranslate

final class CodexConfigOverridesTests: XCTestCase {
    func testConvertsTopLevelValuesAndTables() throws {
        let toml = """
        # comment
        model = "gpt-test" # trailing comment
        model_provider = "gateway"

        [model_providers.gateway]
        name = "Gateway"
        base_url = "https://example.com/v1"
        wire_api = "responses"
        request_max_retries = 4
        """

        let result = try CodexConfigOverrides.importLines(fromTOML: toml)

        XCTAssertEqual(result.lines, [
            "model=\"gpt-test\"",
            "model_provider=\"gateway\"",
            "model_providers.gateway.name=\"Gateway\"",
            "model_providers.gateway.base_url=\"https://example.com/v1\"",
            "model_providers.gateway.wire_api=\"responses\"",
            "model_providers.gateway.request_max_retries=4",
        ])
        XCTAssertEqual(result.disabledKeys, [])
    }

    func testCommentsOutEntriesNotNeededForTranslation() throws {
        let toml = """
        model = "gpt-test"
        notify = ["notifier"]

        [projects."/Users/example/Downloads/repo"]
        trust_level = "trusted"

        [mcp_servers.docs]
        command = "docs-server"
        """

        let result = try CodexConfigOverrides.importLines(fromTOML: toml)

        XCTAssertEqual(result.lines, [
            "model=\"gpt-test\"",
            "# notify=[\"notifier\"]",
            "# projects={\"/Users/example/Downloads/repo\" = {trust_level = \"trusted\"}}",
            "# mcp_servers.docs.command=\"docs-server\"",
        ])
        XCTAssertEqual(result.disabledKeys, ["notify", "projects", "mcp_servers"])
        XCTAssertEqual(CodexConfigOverrides.commandArguments(from: result.lines.joined(separator: "\n")), [
            "-c", "model=\"gpt-test\"",
        ])
    }

    func testUsesInlineTableWhenKeyCannotBeDotted() throws {
        let toml = """
        [model_providers."my.gateway"]
        name = "Gateway"
        env_http_headers = { "X-Api-Key" = "GATEWAY_KEY", "x.trace" = "TRACE_ID" }
        """

        let result = try CodexConfigOverrides.importLines(fromTOML: toml)

        XCTAssertEqual(result.lines, [
            "model_providers={\"my.gateway\" = {name = \"Gateway\", env_http_headers = {X-Api-Key = \"GATEWAY_KEY\", \"x.trace\" = \"TRACE_ID\"}}}",
        ])
    }

    func testFlattensMultilineArraysAndStrings() throws {
        let toml = #"""
        [shell_environment_policy.docs]
        command = "npx"
        args = [
          "-y", # package runner flag
          "docs-server",
        ]
        description = """
        Line one
        Line "two"\
          continued"""
        literal = '''C:\path'''
        """#

        let result = try CodexConfigOverrides.importLines(fromTOML: toml)

        XCTAssertEqual(result.lines, [
            "shell_environment_policy.docs.command=\"npx\"",
            "shell_environment_policy.docs.args=[\"-y\", \"docs-server\"]",
            "shell_environment_policy.docs.description=\"Line one\\nLine \\\"two\\\"continued\"",
            "shell_environment_policy.docs.literal=\"C:\\\\path\"",
        ])
    }

    func testConvertsDottedKeysAndArrayTables() throws {
        let toml = """
        tui.alternate_screen = "never"
        enabled = true
        started = 1979-05-27 07:32:00Z

        [[hooks]]
        event = "start"

        [[hooks]]
        event = "stop"
        """

        let result = try CodexConfigOverrides.importLines(fromTOML: toml)

        XCTAssertEqual(result.lines, [
            "tui.alternate_screen=\"never\"",
            "enabled=true",
            "started=1979-05-27 07:32:00Z",
            "hooks=[{event = \"start\"}, {event = \"stop\"}]",
        ])
    }

    func testReportsLineNumberForInvalidTOML() {
        XCTAssertThrowsError(try CodexConfigOverrides.importLines(fromTOML: "model = \"ok\"\nbroken")) { error in
            XCTAssertEqual((error as? CodexConfigOverrides.ImportError)?.line, 2)
        }
    }

    func testBuildsCommandArgumentsFromNonEmptyLines() {
        let text = """
        model_provider="gateway"

          # disabled="value"
          model_providers.gateway.base_url="https://example.com/v1"
        """

        XCTAssertEqual(CodexConfigOverrides.commandArguments(from: text), [
            "-c", "model_provider=\"gateway\"",
            "-c", "model_providers.gateway.base_url=\"https://example.com/v1\"",
        ])
    }
}

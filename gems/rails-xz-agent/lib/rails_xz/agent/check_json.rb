# frozen_string_literal: true

require "json"
require "open3"
require "rails_xz/toolchain"

module RailsXz
  module Agent
    # Runs the Xz language CLI and parses its JSON diagnostics.
    #
    # The CLI path is resolved through RailsXz::Toolchain (XZ_BIN), never from a
    # bare `xz` (on Linux that is XZ Utils, the compression tool). See
    # docs/07-dev-environment.md section 2.
    class CheckJson
      def initialize(xz_bin: nil, strict: false)
        @xz_bin = xz_bin
        @strict = strict
      end

      # Returns { diagnostics:, exit_status:, stderr: }.
      def call(path)
        args = ["check-json"]
        args << "--strict" if @strict
        args << path
        stdout, stderr, status = Open3.capture3(Toolchain.xz_bin(@xz_bin), *args)
        parse(stdout, stderr, status)
      end

      def parse(stdout, stderr, status)
        raw = JSON.parse(stdout)
        {
          diagnostics: raw.map { |hash| Diagnostic.from_json(hash) },
          exit_status: status.exitstatus,
          stderr: stderr
        }
      rescue JSON::ParserError => e
        raise DiagnosticsParseError, "xz check-json produced invalid JSON: #{e.message}"
      end
    end
  end
end
# frozen_string_literal: true

require "open3"

module RailsXz
  # Resolves the Xz *language* CLI for every Ruby component that shells out to
  # it. Shared by rails-xz-bridge and rails-xz-agent; the canonical rule lives
  # in docs/07-dev-environment.md section 2.
  #
  # On Linux `/usr/bin/xz` is XZ Utils (the compression tool), not the language
  # CLI. A bare `xz` on PATH therefore invokes the wrong program, so the only
  # sanctioned source is the `XZ_BIN` environment variable. An unset, empty, or
  # non-executable value is a hard error: there is no fallback. An executable
  # that is not the language CLI is rejected too, so an `XZ_BIN` pointing at
  # XZ Utils fails loudly instead of silently running the wrong program.
  module Toolchain
    ENV_VAR = "XZ_BIN"

    # The language CLI answers `--version` with its command usage, which lists
    # the `check-json` subcommand; XZ Utils answers with an `xz (XZ Utils)`
    # banner. The probe tells them apart by this marker
    # (docs/07-dev-environment.md section 2).
    LANGUAGE_CLI_MARKER = "check-json"

    Error = Class.new(StandardError)
    MissingCompiler = Class.new(Error)

    module_function

    # Returns the path to the Xz language CLI.
    #
    # Precedence: an explicit override (tests, a per-call choice), then XZ_BIN.
    # Raises MissingCompiler with an actionable message when the value is
    # unset, empty, not an executable file, or not the language CLI.
    def xz_bin(override = nil)
      path = resolve(override)

      raise MissingCompiler, unset_message if path.empty?
      raise MissingCompiler, not_executable_message(path) unless executable_file?(path)
      raise MissingCompiler, not_language_cli_message(path) unless language_cli?(path)

      path
    end

    def configured?
      path = ENV[ENV_VAR].to_s
      !path.empty? && executable_file?(path) && language_cli?(path)
    end

    # Runs `<path> --version` and returns whether the output names the language
    # CLI's subcommands. A path that cannot be run is not the language CLI.
    def language_cli?(path)
      stdout, _stderr, _status = Open3.capture3(path, "--version")
      stdout.include?(LANGUAGE_CLI_MARKER)
    rescue SystemCallError
      false
    end

    def unset_message
      "#{ENV_VAR} is not set; point it at the Xz language CLI " \
        "(docs/07-dev-environment.md section 2)"
    end

    def not_executable_message(path)
      "#{ENV_VAR}=#{path.inspect} is not an executable file; point it at the " \
        "Xz language CLI (docs/07-dev-environment.md section 2)"
    end

    def not_language_cli_message(path)
      "#{ENV_VAR}=#{path.inspect} is not the Xz language CLI: it does not answer " \
        "`--version` with the Xz usage banner. On Linux /usr/bin/xz is XZ Utils, " \
        "the compression tool; point #{ENV_VAR} at the language CLI " \
        "(docs/07-dev-environment.md section 2)"
    end

    def executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    def resolve(override)
      path = override.to_s
      path.empty? ? ENV[ENV_VAR].to_s : path
    end
  end
end

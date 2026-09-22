# frozen_string_literal: true

module RailsXz
  # Resolves the Xz *language* CLI for every Ruby component that shells out to
  # it. Shared by rails-xz-bridge and rails-xz-agent; the canonical rule lives
  # in docs/07-dev-environment.md section 2.
  #
  # On Linux `/usr/bin/xz` is XZ Utils (the compression tool), not the language
  # CLI. A bare `xz` on PATH therefore invokes the wrong program, so the only
  # sanctioned source is the `XZ_BIN` environment variable. An unset, empty, or
  # non-executable value is a hard error: there is no fallback.
  module Toolchain
    ENV_VAR = "XZ_BIN"

    Error = Class.new(StandardError)
    MissingCompiler = Class.new(Error)

    module_function

    # Returns the path to the Xz language CLI.
    #
    # Precedence: an explicit override (tests, a per-call choice), then XZ_BIN.
    # Raises MissingCompiler with an actionable message otherwise.
    def xz_bin(override = nil)
      path = override.to_s
      path = ENV[ENV_VAR].to_s if path.empty?

      raise MissingCompiler, unset_message if path.empty?
      raise MissingCompiler, not_executable_message(path) unless File.executable?(path)

      path
    end

    def configured?
      path = ENV[ENV_VAR].to_s
      !path.empty? && File.executable?(path)
    end

    def unset_message
      "#{ENV_VAR} is not set; point it at the Xz language CLI " \
        "(docs/07-dev-environment.md section 2)"
    end

    def not_executable_message(path)
      "#{ENV_VAR}=#{path.inspect} is not an executable file; point it at the " \
        "Xz language CLI (docs/07-dev-environment.md section 2)"
    end
  end
end
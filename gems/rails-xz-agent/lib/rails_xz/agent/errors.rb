# frozen_string_literal: true

module RailsXz
  module Agent
    Error = Class.new(StandardError)
    MissingCompiler = Class.new(Error)
    DiagnosticsParseError = Class.new(Error)
    RetryExhausted = Class.new(Error)
  end
end
# frozen_string_literal: true

module RailsXz
  module Bridge
    Error = Class.new(StandardError)
    VersionError = Class.new(Error)
    SymbolError = Class.new(Error)
    GenerationError = Class.new(Error)
    MarshallError = Class.new(Error)
    InterfaceError = Class.new(Error)
  end
end
# frozen_string_literal: true

require "rails_xz/toolchain"
require "rails_xz/bridge/version"
require "rails_xz/bridge/errors"
require "rails_xz/bridge/types"
require "rails_xz/bridge/interface"
require "rails_xz/bridge/handle"
require "rails_xz/bridge/values"
require "rails_xz/bridge/loader"
require "rails_xz/bridge/ffi_marshaller"
require "rails_xz/bridge/facade"
require "rails_xz/bridge/generator"

module RailsXz
  # Ruby-side FFI bridge to compiled Xz shared libraries.
  #
  # The build-time entry point is Generator (an .xzint interface becomes a Ruby
  # binding module). The runtime entry point is Loader (a compiled shared
  # object becomes callable symbols). See docs/01-bridge.md.
  module Bridge
  end
end
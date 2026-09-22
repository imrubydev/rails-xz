# frozen_string_literal: true

require "test_helper"

class ToolchainTest < Minitest::Test
  def with_env(value)
    original = ENV["XZ_BIN"]
    ENV["XZ_BIN"] = value
    yield
  ensure
    ENV["XZ_BIN"] = original
  end

  def test_explicit_override_wins_over_env
    with_env("/bin/true") do
      assert_equal "/bin/false", RailsXz::Toolchain.xz_bin("/bin/false")
    end
  end

  def test_env_is_used_without_override
    with_env("/bin/true") do
      assert_equal "/bin/true", RailsXz::Toolchain.xz_bin
    end
  end

  def test_unset_raises_missing_compiler
    with_env(nil) do
      error = assert_raises(RailsXz::Toolchain::MissingCompiler) do
        RailsXz::Toolchain.xz_bin
      end
      assert_includes error.message, "XZ_BIN"
    end
  end

  def test_empty_raises_missing_compiler
    with_env("") do
      assert_raises(RailsXz::Toolchain::MissingCompiler) do
        RailsXz::Toolchain.xz_bin
      end
    end
  end

  def test_non_executable_raises_missing_compiler
    with_env("/does/not/exist/xz") do
      error = assert_raises(RailsXz::Toolchain::MissingCompiler) do
        RailsXz::Toolchain.xz_bin
      end
      assert_includes error.message, "XZ_BIN"
    end
  end

  def test_bare_xz_on_path_is_rejected
    with_env("xz") do
      assert_raises(RailsXz::Toolchain::MissingCompiler) do
        RailsXz::Toolchain.xz_bin
      end
    end
  end

  def test_configured_reflects_a_usable_cli
    with_env(nil) { refute RailsXz::Toolchain.configured? }
    with_env("/bin/true") { assert RailsXz::Toolchain.configured? }
    with_env("/does/not/exist/xz") { refute RailsXz::Toolchain.configured? }
  end
end
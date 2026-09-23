# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ToolchainTest < Minitest::Test
  # The usage banner the Xz language CLI prints for `--version` (it exposes no
  # version string). The probe recognizes it by the `check-json` subcommand.
  LANGUAGE_BANNER =
    "usage: xz <lex|parse|check|check-json|build|run|build-native|bind|fmt|lsp> " \
    "[--strict] [--shared] [--bind python] [--out <path>] [--lang python] " \
    "[--lib <name>] <file.xz>"

  XZ_UTILS_BANNER = "xz (XZ Utils) 5.8.3"

  def with_env(value)
    original = ENV["XZ_BIN"]
    ENV["XZ_BIN"] = value
    yield
  ensure
    ENV["XZ_BIN"] = original
  end

  # A stand-in for the language CLI: it answers `--version` with the usage
  # banner and otherwise succeeds, so the probe accepts it.
  def stub_language_cli(dir, name: "xz", banner: LANGUAGE_BANNER)
    path = File.join(dir, name)
    File.write(path, <<~SH)
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\\n' '#{banner}'
        exit 0
      fi
      exit 0
    SH
    File.chmod(0o755, path)
    path
  end

  def test_explicit_override_wins_over_env
    Dir.mktmpdir("rails-xz-toolchain") do |dir|
      env_cli = stub_language_cli(dir, name: "env-xz")
      override = stub_language_cli(dir, name: "override-xz")

      with_env(env_cli) do
        assert_equal override, RailsXz::Toolchain.xz_bin(override)
      end
    end
  end

  def test_env_is_used_without_override
    Dir.mktmpdir("rails-xz-toolchain") do |dir|
      cli = stub_language_cli(dir)

      with_env(cli) do
        assert_equal cli, RailsXz::Toolchain.xz_bin
      end
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

  def test_a_directory_is_rejected
    Dir.mktmpdir("rails-xz-toolchain") do |dir|
      with_env(dir) do
        error = assert_raises(RailsXz::Toolchain::MissingCompiler) do
          RailsXz::Toolchain.xz_bin
        end
        assert_includes error.message, "not an executable file"
      end
    end
  end

  def test_xz_utils_is_rejected
    Dir.mktmpdir("rails-xz-toolchain") do |dir|
      utils = stub_language_cli(dir, banner: XZ_UTILS_BANNER)

      with_env(utils) do
        error = assert_raises(RailsXz::Toolchain::MissingCompiler) do
          RailsXz::Toolchain.xz_bin
        end
        assert_includes error.message, "not the Xz language CLI"
      end
    end
  end

  def test_configured_reflects_a_usable_cli
    Dir.mktmpdir("rails-xz-toolchain") do |dir|
      cli = stub_language_cli(dir)
      utils = stub_language_cli(dir, name: "xz-utils", banner: XZ_UTILS_BANNER)

      with_env(nil) { refute RailsXz::Toolchain.configured? }
      with_env(cli) { assert RailsXz::Toolchain.configured? }
      with_env(utils) { refute RailsXz::Toolchain.configured? }
      with_env("/does/not/exist/xz") { refute RailsXz::Toolchain.configured? }
    end
  end
end

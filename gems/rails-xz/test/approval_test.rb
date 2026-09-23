# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class ApprovalTest < ActiveSupport::TestCase
  def setup
    RailsXz.reset_config!
    RailsXz::AuditCard.delete_all

    @root = Pathname.new(Dir.mktmpdir)
    FileUtils.mkdir_p(@root.join("app/xz"))
    @root.join("app/xz/order.xz").write("/// @intent Computes the total.\n")
    @root.join("app/xz/order.xzint").write("extern func total() -> Float\n")

    @card = RailsXz::AuditCard.create!(
      module_name: "order",
      intent: "Computes the payable total.",
      source_path: "app/xz/order.xz",
      declared_effects: ["none"],
      derived_effects: ["none"]
    )

    RailsXz.configure do |config|
      config.git_identity = { name: "alice", email: "alice@example.com" }
    end
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.exist?
    RailsXz.reset_config!
    RailsXz::AuditCard.delete_all
  end

  def binder
    ->(_interface) { "# Generated binding\n" }
  end

  def build_runner(fail_on: nil)
    calls = []
    runner = lambda do |argv, env = {}|
      calls << { argv: argv, env: env }
      if argv[0] == "git" && argv[1] == "rev-parse"
        RailsXz::Approval::Outcome.new(stdout: "deadbeef\n", stderr: "", success: true)
      elsif fail_on&.call(argv)
        RailsXz::Approval::Outcome.new(stdout: "", stderr: "boom", success: false)
      else
        RailsXz::Approval::Outcome.new(stdout: "", stderr: "", success: true)
      end
    end
    [runner, calls]
  end

  def approve(card = @card, runner:, **options)
    RailsXz::Approval.call(
      card, by: "alice", root: @root, runner: runner, xz_bin: "/fake/xz",
            **{ binder: binder }.merge(options)
    )
  end

  test "builds, binds, and commits, then approves the card" do
    runner, = build_runner

    result = approve(runner: runner)

    assert_equal "approved", @card.reload.status
    assert_equal "alice", @card.decided_by
    assert_equal "deadbeef", @card.commit_sha
    assert_equal "deadbeef", result.commit_sha
    assert_equal @root.join("app/xz/bindings/order.rb").to_s, result.binding_path
    assert_equal "# Generated binding\n",
                 @root.join("app/xz/bindings/order.rb").read
  end

  test "runs xz build --shared with the configured output and source" do
    runner, calls = build_runner

    approve(runner: runner)

    build = calls.find { |call| call[:argv][1] == "build" }[:argv]
    assert_equal(
      ["/fake/xz", "build", "--shared", "--out",
       @root.join("vendor/xz/order.so").to_s,
       @root.join("app/xz/order.xz").to_s],
      build
    )
  end

  test "commits the source, interface, and binding under the approving identity" do
    runner, calls = build_runner

    approve(runner: runner)

    add = calls.find { |call| call[:argv][1] == "add" }
    assert_equal(
      ["git", "add", "--", "app/xz/order.xz", "app/xz/order.xzint",
       "app/xz/bindings/order.rb"],
      add[:argv]
    )
    assert_equal "alice", add[:env]["GIT_AUTHOR_NAME"]
    assert_equal "alice@example.com", add[:env]["GIT_COMMITTER_EMAIL"]

    commit = calls.find { |call| call[:argv][1] == "commit" }
    assert_includes commit[:argv], "xz: Computes the payable total."
  end

  test "derives the commit message from the module name when intent is blank" do
    @card.update!(intent: nil)
    runner, calls = build_runner

    approve(runner: runner)

    commit = calls.find { |call| call[:argv][1] == "commit" }
    assert_includes commit[:argv], "xz: order"
  end

  test "refuses a card that is not pending" do
    @card.approve!(by: "bob")
    runner, = build_runner

    assert_raises(RailsXz::Approval::AlreadyDecided) { approve(runner: runner) }
  end

  test "requires a source_path" do
    @card.update!(source_path: nil)
    runner, = build_runner

    assert_raises(RailsXz::Approval::MissingSource) { approve(runner: runner) }
  end

  test "requires the .xzint interface beside the source" do
    File.delete(@root.join("app/xz/order.xzint"))
    runner, = build_runner

    assert_raises(RailsXz::Approval::MissingInterface) { approve(runner: runner) }
  end

  test "leaves the card pending when the build fails" do
    runner, = build_runner(fail_on: ->(argv) { argv[1] == "build" })

    assert_raises(RailsXz::Approval::BuildFailed) { approve(runner: runner) }
    assert_equal "pending", @card.reload.status
  end

  test "reports a missing compiler as a build failure" do
    runner, = build_runner
    original = ENV["XZ_BIN"]
    ENV.delete("XZ_BIN")

    error = assert_raises(RailsXz::Approval::BuildFailed) do
      RailsXz::Approval.call(@card, by: "alice", root: @root, runner: runner,
                                    binder: binder)
    end
    assert_match "XZ_BIN", error.message
  ensure
    ENV["XZ_BIN"] = original
  end

  test "requires a git identity and never falls back to the global one" do
    RailsXz.reset_config!
    runner, = build_runner

    assert_raises(RailsXz::Approval::MissingGitIdentity) { approve(runner: runner) }
    assert_equal "pending", @card.reload.status
  end

  test "leaves the card pending when the commit fails" do
    runner, = build_runner(fail_on: ->(argv) { argv[1] == "commit" })

    assert_raises(RailsXz::Approval::CommitFailed) { approve(runner: runner) }
    assert_equal "pending", @card.reload.status
  end

  test "surfaces a binding generation failure" do
    runner, = build_runner
    failing_binder = ->(_interface) { raise RailsXz::Bridge::GenerationError, "bad interface" }

    error = assert_raises(RailsXz::Approval::BindFailed) do
      approve(runner: runner, binder: failing_binder)
    end
    assert_match "bad interface", error.message
    assert_equal "pending", @card.reload.status
  end
end

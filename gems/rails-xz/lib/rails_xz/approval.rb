# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

module RailsXz
  # The P1 approval action: build the shared library, regenerate the Ruby
  # binding, and commit all three under the approving developer's identity.
  # See docs/03-audit-engine.md section 5.
  #
  #   RailsXz::Approval.call(card, by: "alice")
  #
  # The steps run in order and the card is marked approved only after all three
  # succeed, so a failed build never records a decision. A card that is not
  # `pending` raises `AlreadyDecided`.
  class Approval
    Outcome = Struct.new(:stdout, :stderr, :success, keyword_init: true) do
      def success?
        success
      end
    end

    Result = Struct.new(:library_path, :binding_path, :commit_sha, keyword_init: true)

    Paths = Struct.new(:source, :interface, :library, :binding, :stem, keyword_init: true)

    class Error < StandardError; end
    MissingSource = Class.new(Error)
    MissingInterface = Class.new(Error)
    MissingGitIdentity = Class.new(Error)
    BuildFailed = Class.new(Error)
    BindFailed = Class.new(Error)
    CommitFailed = Class.new(Error)
    AlreadyDecided = Class.new(Error)

    def self.call(card, by:, **options)
      new(card, by: by, **options).call
    end

    def initialize(card, by:, root: Rails.root, config: RailsXz.config,
                   runner: nil, binder: nil, xz_bin: nil)
      @card = card
      @by = by
      @root = Pathname.new(root.to_s)
      @config = config
      @runner = runner || method(:capture)
      @binder = binder || method(:generate_binding)
      @xz_bin = xz_bin
    end

    def call
      guard!
      paths = resolve_paths
      build!(paths)
      bind!(paths)
      sha = commit!(paths)
      @card.approve!(by: @by, commit_sha: sha)
      Result.new(library_path: paths.library.to_s,
                 binding_path: paths.binding.to_s,
                 commit_sha: sha)
    end

    private

    def guard!
      return if @card.pending?

      raise AlreadyDecided, "card #{@card.id} is #{@card.status}, not pending"
    end

    def resolve_paths
      relative = @card.source_path.to_s
      raise MissingSource, "card #{@card.id} has no source_path" if relative.strip.empty?

      source = @root.join(relative)
      raise MissingSource, "source #{relative} does not exist" unless source.file?

      interface = source.sub_ext(".xzint")
      unless interface.file?
        raise MissingInterface,
              "no .xzint interface beside #{relative} " \
              "(expected #{interface.relative_path_from(@root)})"
      end

      stem = source.basename(".xz").to_s
      Paths.new(
        source: source,
        interface: interface,
        library: @root.join(@config.build_root, "#{stem}#{platform_suffix}"),
        binding: @root.join(@config.bindings_root, "#{stem}.rb"),
        stem: stem
      )
    end

    def build!(paths)
      FileUtils.mkdir_p(paths.library.dirname)
      outcome = @runner.call(
        [xz_bin, "build", "--shared", "--out", paths.library.to_s, paths.source.to_s]
      )
      return if outcome.success?

      raise BuildFailed, command_failure("xz build --shared", outcome)
    rescue Toolchain::Error => e
      raise BuildFailed, "xz build --shared failed: #{e.message}"
    end

    def bind!(paths)
      source = @binder.call(paths.interface.to_s)
      FileUtils.mkdir_p(paths.binding.dirname)
      File.write(paths.binding, source)
    rescue Bridge::Error => e
      raise BindFailed, "binding generation failed: #{e.message}"
    end

    def commit!(paths)
      env = git_identity_env
      files = [paths.source, paths.interface, paths.binding]
              .map { |path| path.relative_path_from(@root).to_s }

      add = @runner.call(["git", "add", "--", *files], env)
      raise CommitFailed, command_failure("git add", add) unless add.success?

      commit = @runner.call(["git", "commit", "-m", commit_message, "--", *files], env)
      raise CommitFailed, command_failure("git commit", commit) unless commit.success?

      rev = @runner.call(["git", "rev-parse", "HEAD"], env)
      raise CommitFailed, command_failure("git rev-parse", rev) unless rev.success?

      rev.stdout.strip
    end

    def git_identity_env
      identity = @config.git_identity
      unless identity.is_a?(Hash) && present?(identity[:name]) && present?(identity[:email])
        raise MissingGitIdentity,
              "RailsXz.config.git_identity must be { name:, email: } for the approval commit"
      end

      name = identity[:name].to_s
      email = identity[:email].to_s
      {
        "GIT_AUTHOR_NAME" => name,
        "GIT_AUTHOR_EMAIL" => email,
        "GIT_COMMITTER_NAME" => name,
        "GIT_COMMITTER_EMAIL" => email
      }
    end

    def commit_message
      intent = @card.intent.to_s.strip.lines.first.to_s.strip
      intent = @card.module_name.to_s if intent.empty?
      "xz: #{intent}"
    end

    def generate_binding(interface)
      Bridge::Generator.new(interface).generate
    end

    def platform_suffix
      Bridge::Generator::PLATFORM_SUFFIX
    end

    def xz_bin
      @xz_bin || Toolchain.xz_bin
    end

    def capture(argv, env = {})
      out, err, status = Open3.capture3(env, *argv, chdir: @root.to_s)
      Outcome.new(stdout: out, stderr: err, success: status.success?)
    end

    def command_failure(label, outcome)
      detail = [outcome.stderr, outcome.stdout]
               .map(&:to_s).map(&:strip).reject(&:empty?).join("\n")
      detail.empty? ? "#{label} failed" : "#{label} failed: #{detail}"
    end

    def present?(value)
      !value.to_s.strip.empty?
    end
  end
end

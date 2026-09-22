# frozen_string_literal: true

require "rake/testtask"

GEM_DIRS = Dir[File.expand_path("gems/*", __dir__)]

desc "Run the test suite of every gem"
task :test do
  failed = []
  GEM_DIRS.each do |dir|
    next unless File.exist?(File.join(dir, "Rakefile"))
    puts "\n==> #{File.basename(dir)}"
    ok = system("bundle", "exec", "rake", "-f", File.join(dir, "Rakefile"), "test", chdir: dir)
    failed << File.basename(dir) unless ok
  end
  abort("test failures: #{failed.join(', ')}") unless failed.empty?
end

task default: :test
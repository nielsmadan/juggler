require "cask/cask"
require "cask/config"
require "cask/installer"
require "tmpdir"

class FixtureCask < Cask::Cask
  def initialize(token, root, &block)
    @fixture_root = root
    super(token, config: Cask::Config.new(explicit: { appdir: root/"Applications" }), &block)
  end

  def caskroom_path
    @fixture_root/"Caskroom"/token
  end
end

class FixtureLoader
  def initialize(root)
    @root = root
  end

  def cask(token, &block)
    FixtureCask.new(token, @root, &block)
  end
end

repo = Pathname(__dir__).parent.parent
template = (repo/"homebrew/juggler.rb.in").read
source = template.gsub("@VERSION@", "1.7.3").gsub("@SHA256@", "a" * 64)

{ "1.7.1" => true, "1.7.3" => false, "1.7.4" => false }.each do |app_version, outdated|
  Dir.mktmpdir("juggler-sparkle-") do |directory|
    cask = FixtureLoader.new(Pathname(directory)).instance_eval(source, "juggler.rb")
    cask.define_singleton_method(:installed_version) { "1.7.1" }
    plist = cask.config.appdir/"Juggler.app/Contents/Info.plist"
    plist.dirname.mkpath
    plist.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>#{app_version}</string>
        <key>CFBundleVersion</key><string>1</string>
      </dict></plist>
    XML
    raise "Incorrect upgrade decision for Sparkle version #{app_version}" unless cask.outdated? == outdated
  end
end
puts "PASS: Sparkle updates with an older Homebrew receipt"

[:uninstall, :upgrade, :reinstall, :zap, :zap_failure].each do |operation|
  Dir.mktmpdir("juggler-homebrew-") do |directory|
    root = Pathname(directory)
    cask = FixtureLoader.new(root).instance_eval(source, "juggler.rb")
    requirement = cask.depends_on.macos
    raise "Incorrect minimum macOS" unless requirement.comparator == ">=" && requirement.version == MacOSVersion.new("15")
    app = cask.config.appdir/"Juggler.app"
    resources = app/"Contents/Resources"
    resources.mkpath
    %w[uninstall.sh integration_cleanup.py codex_config_cleanup.py].each do |name|
      origin = repo/"juggler/Resources"/name
      origin = repo/"juggler/Resources/hooks"/name if name == "uninstall.sh"
      FileUtils.cp(origin, resources/name)
    end
    cask.staged_path.mkpath
    FileUtils.ln_s(app, cask.staged_path/"Juggler.app")

    user_directory = root/"User"
    extension = user_directory/".pi/agent/extensions/juggler-pi.ts"
    extension.dirname.mkpath
    extension.write("installed")
    if operation == :zap_failure
      settings = user_directory/".claude/settings.json"
      settings.dirname.mkpath
      settings.write("{broken")
    end
    uninstall = cask.artifacts.grep(Cask::Artifact::Uninstall).fetch(0)
    uninstall.define_singleton_method(:uninstall_quit) do |*bundle_ids, **|
      raise "Wrong application quit target" unless bundle_ids == ["com.nielsmadan.Juggler"]
    end
    zap = cask.artifacts.grep(Cask::Artifact::Zap).fetch(0)
    zap.directives[:script][:args] = ["--home-directory", user_directory.to_s, "--skip-permissions"]
    fixture_environment = {
      "XDG_CONFIG_HOME" => (user_directory/".config").to_s,
      "KITTY_CONFIG_DIRECTORY" => (user_directory/".config/kitty").to_s,
      "OPENCODE_CONFIG_DIR" => (user_directory/".config/opencode").to_s,
      "PI_CODING_AGENT_DIR" => (user_directory/".pi/agent").to_s,
    }
    command_runner = Class.new(SystemCommand)
    command_runner.define_singleton_method(:run) do |executable, **options|
      SystemCommand.run(executable, **options, env: fixture_environment)
    end
    trashed = []
    zap.define_singleton_method(:uninstall_trash) do |*paths, **|
      trashed.concat(paths)
    end

    installer = Cask::Installer.new(cask, upgrade: operation == :upgrade, reinstall: operation == :reinstall)
    installer.uninstall_artifacts
    raise "App was not removed from custom appdir" if app.exist?
    raise "Integration removed during #{operation}" unless extension.read == "installed"

    if operation == :zap
      zap.zap_phase(command: command_runner)
      raise "Zap left the extension installed" if extension.exist?
      expected = ["~/Library/Application Support/Juggler", "~/Library/Caches/com.nielsmadan.Juggler",
                  "~/Library/Preferences/com.nielsmadan.Juggler.plist"]
      raise "Unexpected zap paths: #{trashed.inspect}" unless trashed == expected
    elsif operation == :zap_failure
      begin
        zap.zap_phase(command: command_runner)
        raise "Zap accepted failed integration cleanup"
      rescue ErrorDuringExecution
        raise "Zap trashed preferences after cleanup failed" unless trashed.empty?
        raise "Staged app was lost after cleanup failed" unless (cask.staged_path/"Juggler.app").directory?
      end
    end
    puts "PASS: #{operation}"
  end
end

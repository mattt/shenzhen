command :build do |c|
  c.syntax = 'ipa build [options]'
  c.summary = 'Create a new .ipa file for your app'
  c.description = ''

  c.option '-w', '--workspace WORKSPACE', 'Workspace (.xcworkspace) file to use to build app (automatically detected in current directory)'
  c.option '-p', '--project PROJECT', 'Project (.xcodeproj) file to use to build app (automatically detected in current directory, overridden by --workspace option, if passed)'
  c.option '-c', '--configuration CONFIGURATION', 'Configuration used to build'
  c.option '-s', '--scheme SCHEME', 'Scheme used to build app'
  c.option '-g', '--tag', 'Tag current version in git with the format version(build)'
  c.option '-i', '--increase-build', 'Increase the build number'
  c.option '--[no-]clean', 'Clean project before building'
  c.option '--[no-]archive', 'Archive project after building'

  c.action do |args, options|
    validate_xcode_version!

    @workspace = options.workspace
    @project = options.project unless @workspace

    @xcodebuild_info = Shenzhen::XcodeBuild.info(:workspace => @workspace, :project => @project)

    @scheme = options.scheme
    @configuration = options.configuration

    determine_workspace_or_project! unless @workspace || @project

    determine_configuration! unless @configuration
    say_error "Configuration #{@configuration} not found" and abort unless (@xcodebuild_info.build_configurations.include?(@configuration) rescue false)

    determine_scheme! unless @scheme
    say_error "Scheme #{@scheme} not found" and abort unless (@xcodebuild_info.schemes.include?(@scheme) rescue false)

    say_warning "Building \"#{@workspace || @project}\" with Scheme \"#{@scheme}\" and Configuration \"#{@configuration}\"\n" unless options.quiet

    log "xcodebuild", (@workspace || @project)

    flags = []
    flags << "-sdk iphoneos"
    flags << "-workspace '#{@workspace}'" if @workspace
    flags << "-project '#{@project}'" if @project
    flags << "-scheme '#{@scheme}'" if @scheme
    flags << "-configuration '#{@configuration}'"

    actions = []
    actions << :clean unless options.clean == false
    actions << :build
    actions << :archive unless options.archive == false

    #increase build version
    @target, @xcodebuild_settings = Shenzhen::XcodeBuild.settings(*flags).detect{|target, settings| settings['WRAPPER_EXTENSION'] == "app"}
    say_error "App settings could not be found." and abort unless @xcodebuild_settings

    determine_info_plist

    increase_build_number if options.increase_build
    tag_build if options.tag
    ENV['CC'] = nil # Fix for RVM
    abort unless system %{xcodebuild #{flags.join(' ')} #{actions.join(' ')} 1> /dev/null}

    @app_path = File.join(@xcodebuild_settings['BUILT_PRODUCTS_DIR'], @xcodebuild_settings['WRAPPER_NAME'])
    @dsym_path = @app_path + ".dSYM"
    @dsym_filename = "#{@xcodebuild_settings['WRAPPER_NAME']}.dSYM"
    @ipa_name = @xcodebuild_settings['WRAPPER_NAME'].gsub(@xcodebuild_settings['WRAPPER_SUFFIX'], "") + ".ipa"
    @ipa_path = File.join(Dir.pwd, @ipa_name)

    log "xcrun", "PackageApplication"
    abort unless system %{xcrun -sdk iphoneos PackageApplication -v "#{@app_path}" -o "#{@ipa_path}" --embed "#{@dsym_path}" 1> /dev/null}

    log "zip", @dsym_filename
    abort unless system %{cp -r "#{@dsym_path}" . && zip -r "#{@dsym_filename}.zip" "#{@dsym_filename}" >/dev/null && rm -rf "#{@dsym_filename}"}

    say_ok "#{File.basename(@ipa_path)} successfully built" unless options.quiet
  end

  private

  def validate_xcode_version!
    version = Shenzhen::XcodeBuild.version
    say_error "Shenzhen requires Xcode 4 (found #{version}). Please install or switch to the latest Xcode." and abort if version < "4.0.0"
  end

  def determine_workspace_or_project!
    workspaces, projects = Dir["*.xcworkspace"], Dir["*.xcodeproj"]

    if workspaces.empty?
      if projects.empty?
        say_error "No Xcode projects or workspaces found in current directory" and abort
      else
        if projects.length == 1
          @project = projects.first
        else
          @project = choose "Select a project:", *projects
        end
      end
    else
      if workspaces.length == 1
        @workspace = workspaces.first
      else
        @workspace = choose "Select a workspace:", *workspaces
      end
    end
  end

  def determine_scheme!
    if @xcodebuild_info.schemes.length == 1
      @scheme = @xcodebuild_info.schemes.first
    else
      @scheme = choose "Select a scheme:", *@xcodebuild_info.schemes
    end
  end

  def determine_configuration!
    configurations = @xcodebuild_info.build_configurations rescue []
    if configurations.nil? or configurations.empty? or configurations.include?("Debug")
      @configuration = "Debug"
    elsif configurations.length == 1
      @configuration = configurations.first
    end

    if @configuration
      say_warning "Configuration was not passed, defaulting to #{@configuration}"
    else
      @configuration = choose "Select a configuration:", *configurations
    end
  end

  def determine_project_directory
    @project_dir ||= @workspace ? File.dirname(@workspace) : File.dirname(@project)
  end

  def determine_info_plist
    determine_project_directory

    @info_plist_path = File.join(@project_dir, @xcodebuild_settings['INFOPLIST_FILE'])
  end

  def increase_build_number
    @previous_build_number = Shenzhen::PlistBuddy.print(@info_plist_path,"CFBundleVersion")
    @current_build_number = @previous_build_number.to_i + 1

    Shenzhen::PlistBuddy.set(@info_plist_path,"CFBundleVersion",@current_build_number)
    say_ok "Increasing build to #{@current_build_number.to_i}"
  end

  def tag_build
    process_tag_names
    tag_current_version
  end

  def process_tag_names
    @last_tag_name=`git describe --abbrev=0 --tags`.strip!
    @current_build_number ||= Shenzhen::PlistBuddy.print(@info_plist_path,"CFBundleVersion")
    @current_build_version ||= Shenzhen::PlistBuddy.print(@info_plist_path,"CFBundleShortVersionString")
    @current_tag_name="#{@current_build_version}(#{@current_build_number})"      
  end

  def tag_current_version
    determine_project_directory

    say_ok "Create tag for build #{@current_tag_name}"
    log `cd #{@project_dir} && git tag "#{@current_tag_name}"`
  end
end

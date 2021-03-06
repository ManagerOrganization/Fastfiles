fastlane_version "1.102.0"

default_platform :ios

platform :ios do

  ENV['HIPCHAT_API_VERSION'] = '2'
  ENV['HIPCHAT_API_HOST'] = 'hipchat.host'
  ENV['HIPCHAT_NOTIFY_ROOM'] = 'true'
  ENV['FL_HIPCHAT_CHANNEL'] = "iOSTeam"
  ENV['HIPCHAT_API_TOKEN'] = "token"
  ENV['FL_AUTOMATION_TEMPLATE'] = '/Applications/Xcode.app/Contents/Applications/Instruments.app/Contents/PlugIns/AutomationInstrument.xrplugin/Contents/Resources/Automation.tracetemplate'

  MASTER_PATH    = "https://github.com/CocoaPods/Specs"
  PRIVATE_PATH   = "git@git.gengmei.cc:gengmeiios/GMSpecs.git"
  SOURCES        = [MASTER_PATH, PRIVATE_PATH]
  
  desc 'Deploy a new version to the App Store'
  lane :do_deliver_app do |options|
    app_identifier   = options[:app_identifier]
    project          = options[:project]
    scheme           = options[:scheme]
    version          = options[:version] 
    build            = options[:build] || Time.now.strftime('%Y%m%d%H%M')
    output_directory = options[:output_directory]
    output_name      = options[:output_name]
    
    hipchat(message: "Start deilver app #{project} at version #{version}")
    
    hipchat(message: "Git pull")
    git_pull

    hipchat(message: "Pod install")
    cocoapods

    cert(username: ENV["FASTLANE_USER"])
    sigh(force: true, username: ENV["FASTLANE_USER"], app_identifier: app_identifier)
    
    hipchat(message: "Update build number to #{build} and building ipa")
    update_build_number(version: build, plist: "#{project}/Info.plist")
    gym(scheme: options[:scheme], clean: true, output_directory: output_directory, output_name: output_name)

    hipchat(message: 'deliver to itunesconnect')
    deliver(force: false, skip_screenshots: true, skip_metadata: true)

    hipchat(message: "Upload #{project} to itunesconnect successfully!")
    
    git_add(path: '.')
    git_commit(path: '.', message: "update build number to #{build} and upload to itunesconnect")
    git_pull
    git_push(branch: "test")
  end
  
  desc "Release new private pod version"
  lane :do_release_lib do |options|
    target_version = options[:version]
    project        = options[:project]
    path           = "#{project}.podspec"
    
    hipchat(message: "Start release pod #{project} at version #{target_version}")
    
    git_pull
    ensure_git_branch # 确认 master 分支
    pod_install
    pod_lib_lint(verbose: true, allow_warnings: true, sources: SOURCES, use_bundle_exec: true, fail_fast: true)
    version_bump_podspec(path: path, version_number: target_version) # 更新 podspec
    git_commit_all(message: "Bump version to #{target_version}") # 提交版本号修改
    add_git_tag(tag: target_version) # 设置 tag
    push_to_git_remote # 推送到 git 仓库
    pod_push(path: path, repo: "GMSpecs", allow_warnings: true, sources: SOURCES) # 提交到 CocoaPods
    
    hipchat(message: "Release pod #{project} Successfully!")
  end

  desc "UI automation test"
  lane :do_monkey_test do |options|
    times              = options[:times] || 2 
    scheme             = options[:scheme]
    project            = options[:project]
    device_udid        = options[:device_udid]
    device_type        = options[:device_type]
    script             = options[:script]
    report_output_path = options[:report_output_path]
    
    hipchat(message: "Start monkey test on #{project}")
    
    git_pull
    cocoapods
    xcodebuild(scheme: scheme, arch: 'x86_64', sdk: 'iphonesimulator9.3', workspace: "#{project}.xcworkspace", configuration: 'Debug')
    app_path = get_debug_app_path(scheme: scheme, project: project)
    (1..times.to_i).each do |i|
      install_app_on_simulator(device_type: device_type, app_path: app_path) # 使用ios-sim命令安装app到模拟器，如果是真机的话，则使用ios-deploy
      sleep(30)
      instruments_ui_automation(device: device_udid, app_path: app_path, report_output_path: report_output_path, script:script)
    end
    
    hipchat(message: "Execute monkey test on #{project} successfully")
  end

  error do |lane, exception|
    hipchat(
    custom_color: 'red',
    message: exception.message,
    success: false
    )
  end

end

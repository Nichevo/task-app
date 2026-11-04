# Adds the iPad/iPhone widget extension (ios/TaskBlocksWidget) to ios/Runner.xcodeproj.
# Run from the repo root with: ruby tool/ios_widget_target.rb   (needs: gem install xcodeproj)
# Safe to run again: it does nothing when the target is already there.
require 'xcodeproj'

NAME = 'TaskBlocksWidget'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner
if project.targets.any? { |t| t.name == NAME }
  puts "#{NAME} is already in the project"
  exit
end

widget = project.new_target(:app_extension, NAME, :ios, '17.0', nil, :swift)
# xcodeproj links Foundation by a path inside this machine's SDK; Swift links it by itself.
widget.frameworks_build_phase.files.dup.each do |bf|
  ref = bf.file_ref
  widget.frameworks_build_phase.remove_build_file(bf)
  ref&.remove_from_project
end
fw = project.main_group['Frameworks']
if fw
  fw.recursive_children.each { |c| c.remove_from_project if c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.children.empty? }
  fw.remove_from_project if fw.children.empty?
end

# Same configurations as Runner (Debug, Release, Profile), on Flutter's xcconfig files so the
# widget gets the app's version numbers.
flutter_group = project.main_group['Flutter']
xcconfig = ->(n) { flutter_group.files.find { |f| File.basename(f.path) == "#{n}.xcconfig" } or abort "#{n}.xcconfig not found" }
runner.build_configurations.each do |rc|
  bc = widget.build_configurations.find { |c| c.name == rc.name } || widget.add_build_configuration(rc.name, rc.name == 'Debug' ? :debug : :release)
  bc.base_configuration_reference = xcconfig.(rc.name == 'Debug' ? 'Debug' : 'Release')
  s = bc.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.taskblocks.widget'
  s['INFOPLIST_FILE'] = "#{NAME}/Info.plist"
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = "#{NAME}/#{NAME}.entitlements"
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SWIFT_VERSION'] = '5.0'
  s['SKIP_INSTALL'] = 'YES'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  s['SWIFT_OPTIMIZATION_LEVEL'] = rc.name == 'Debug' ? '-Onone' : '-O'
end

# Source files: the widget's own folder, plus ios/Shared (used by the app and the widget).
widget_group = project.main_group.new_group(NAME, NAME)
swift = widget_group.new_file('TaskBlocksWidget.swift')
widget_group.new_file('Info.plist')
widget_group.new_file("#{NAME}.entitlements")
widget.add_file_references([swift])

shared_group = project.main_group.new_group('Shared', 'Shared')
app_group = shared_group.new_file('AppGroup.swift')
widget.add_file_references([app_group])
runner.add_file_references([app_group])

runner_group = project.main_group['Runner']
runner_group.new_file('Runner.entitlements') unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
runner.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements' }

# Build the widget before the app and copy it into Runner.app/PlugIns. The copy step sits before
# Flutter's "Thin Binary" script, otherwise Xcode reports a dependency cycle.
runner.add_dependency(widget)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(runner.build_phases.index(thin), embed)
end

project.save
puts "Added #{NAME}"

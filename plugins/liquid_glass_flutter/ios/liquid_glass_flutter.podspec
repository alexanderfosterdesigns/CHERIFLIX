Pod::Spec.new do |s|
  s.name             = 'liquid_glass_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Native iOS 26 liquid glass surfaces for Flutter.'
  s.description      = <<-DESC
Expose iOS 26 liquid glass surfaces to Flutter and provide a layered fallback
renderer for unsupported platforms.
                       DESC
  s.homepage         = 'https://github.com/callstack/liquid-glass'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Codex' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17'
  }
  s.swift_version = '5.0'
end

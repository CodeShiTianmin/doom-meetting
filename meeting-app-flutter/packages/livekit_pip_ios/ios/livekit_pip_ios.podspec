#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'livekit_pip_ios'
  s.version          = '0.0.1'
  s.summary          = 'An iOS implementation of the livekit_pip plugin.'
  s.description      = <<-DESC
  Native Picture-in-Picture for LiveKit video calls — iOS implementation.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Dev Kaffah' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'livekit_pip_ios/Sources/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
  s.platform         = :ios, '16.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }
  s.swift_version = '5.0'
end

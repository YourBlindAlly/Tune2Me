Pod::Spec.new do |s|
  s.name           = 'Tune2MeAudioEngine'
  s.version        = '1.0.0'
  s.summary        = 'Real-time pitch detection and reference-tone synthesis'
  s.description    = 'Native AVAudioEngine wrapper: forces built-in-mic input, measurement-mode session, YIN pitch detection, and harmonic-stack tone synthesis.'
  s.author         = ''
  s.homepage       = 'https://github.com/YourBlindAlly/Tune2Me'
  s.platforms      = { :ios => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end

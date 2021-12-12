
Pod::Spec.new do |s|
  s.name             = 'SSURLSession'
  s.version          = '0.1.1'
  s.summary          = ' 拆分于Swift FoundationNetworking 库，release/5.6版本，增加了设置resolve和connectTo的能力，可用于IP直连解决设置SNI无法设置的问题 '
  s.homepage         = 'https://github.com/zhtut/SSURLSession'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ztgtut' => 'ztgtut@github.com' }
  s.source           = { :git => 'https://github.com/zhtut/SSURLSession.git', :tag => s.version.to_s }

  s.swift_version = '5.0'
  s.ios.deployment_target = '9.0'

  s.source_files = '**/*.swift'
  s.module_name = 'SSURLSession'
  s.header_dir = 'SSURLSession'

  s.dependency 'CFURLSessionInterface'
  
end

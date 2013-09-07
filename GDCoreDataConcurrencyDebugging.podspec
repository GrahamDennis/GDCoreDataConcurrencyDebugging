Pod::Spec.new do |s|
  s.name         = "GDCoreDataConcurrencyDebugging"
  s.version      = "0.1.0"
  s.summary      = "A short description of GDCoreDataConcurrencyDebugging."
  s.description  = <<-DESC
                    An optional longer description of GDCoreDataConcurrencyDebugging

                    * Markdown format.
                    * Don't worry about the indent, we strip it!
                   DESC
  s.homepage     = "http://github.com/GrahamDennis/GDCoreDataConcurrencyDebugging"
  s.license      = 'BSD'
  s.author       = { "Graham Dennis" => "graham@grahamdennis.me" }
  s.source       = { :git => "http://github.com/GrahamDennis/GDCoreDataConcurrencyDebugging.git", :tag => s.version.to_s }

  # s.platform     = :ios, '5.0'
  # s.ios.deployment_target = '5.0'
  # s.osx.deployment_target = '10.7'
  s.requires_arc = false

  s.source_files = 'Classes'

  s.ios.exclude_files = 'Classes/osx'
  s.osx.exclude_files = 'Classes/ios'
  # s.public_header_files = 'Classes/**/*.h'
  # s.frameworks = 'SomeFramework', 'AnotherFramework'
  s.dependency 'JRSwizzle'
end

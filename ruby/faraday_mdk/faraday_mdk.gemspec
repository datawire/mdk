Gem::Specification.new do |s|
  s.add_dependency 'faraday', ['>= 0.8', '<0.10']
  s.name        = 'faraday_mdk'
  s.version     = '2.0.28'
  s.summary     = "Datawire MDK integration Rack middleware."
  s.authors     = ["Datawire Inc."]
  s.files       = ["lib/faraday_mdk.rb"]
  s.homepage    = 'https://github.com/datawire/mdk'
  s.license     = 'Apache-2.0'
end

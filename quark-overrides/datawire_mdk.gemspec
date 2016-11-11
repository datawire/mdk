Gem::Specification.new do |spec|
  spec.name        = 'datawire_mdk'
  spec.version     = '2.0.31'
  spec.summary     = 'Microservices Development Kit: build your own microservices.'
  spec.author      = 'Datawire.io'
  spec.license     = 'Apache-2.0'
  spec.files       = Dir["{lib}/**/*.rb"]
  spec.homepage    = 'https://www.datawire.io'
  spec.add_runtime_dependency 'concurrent-ruby', '= 1.0.1'
  spec.add_runtime_dependency 'reel', '= 0.6.1'
  spec.add_runtime_dependency 'websocket-driver', '= 0.6.3'
  spec.add_runtime_dependency 'logging', '= 2.1.0'
  spec.add_runtime_dependency 'event_emitter', '= 0.2.5'
end

$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "strongly_typed_parameters/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "strongly_typed_parameters"
  s.version     = StronglyTypedParameters::VERSION
  s.authors     = ["David Heinemeier Hansson", "Aaron Weiner"]
  s.email       = ["aweiner@mdsol.com"]
  s.summary     = "Whitelist and typecheck your parameters at the controller level"
  s.homepage    = "https://github.com/mdsol/strong_parameters"

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "actionpack", "~> 3.0"
  s.add_dependency "activemodel", "~> 3.0"
  s.add_dependency "railties", "~> 3.0"

  s.add_development_dependency "rake"
  s.add_development_dependency "mocha", "~> 0.12.0"

end

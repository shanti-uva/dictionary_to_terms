$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "dictionary_to_terms/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "dictionary_to_terms"
  s.version     = DictionaryToTerms::VERSION
  s.authors     = ["Andres Montano"]
  s.email       = ["amontano@virginia.edu"]
  s.homepage    = "http://terms.kmaps.virginia.edu"
  s.summary     = "Engine used to export tibetan dictionary into terms dictionary."
  s.description = "Engine used to export tibetan dictionary into terms dictionary."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.1.4"

  s.add_development_dependency "pg"
end

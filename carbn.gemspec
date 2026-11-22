# frozen_string_literal: true
require_relative "lib/carbn"

Gem::Specification.new do |spec|
  spec.name = "carbn"
  spec.version = Carbn::VERSION
  spec.summary = "Reactive Ruby projections and ViewComponent rendering boundaries"
  spec.authors = ["Carbn contributors"]
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.add_development_dependency "minitest", ">= 5.0"
end

# frozen_string_literal: true
require_relative "../lib/carbn"

# Completely independent consumer: no Diesl, Rails or browser.
graph = Carbn::Graph.define do
  state :clicks, initial: 0
  derive(:label, from: [:clicks]) { |count| "Clicks: #{count}" }
  region :counter, depends_on: [:label]
end
store = Carbn::Store.new(graph)
store.subscribe { |regions, revision| puts "Revision #{revision}: #{regions.join(', ')} -> #{store.get(:label)}" }
store.set(:clicks, 1)

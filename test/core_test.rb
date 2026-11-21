# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/carbn"

class CarbnCoreTest < Minitest::Test
  def setup
    @graph = Carbn::Graph.define do
      state :value, initial: 1
      state :name, initial: "demo"
      derive(:double, from: [:value]) { |value| value * 2 }
      derive(:label, from: [:double, :name]) { |value, name| "#{name}: #{value}" }
      region :counter, depends_on: [:double]
      region :heading, depends_on: [:label]
    end
  end

  def test_derivation_order_and_minimal_invalidation
    store = Carbn::Store.new(@graph)
    seen = []
    store.subscribe { |regions, revision| seen << [regions, revision] }
    assert_equal "demo: 2", store.get(:label)
    store.set(:value, 2)
    assert_equal [[[:counter, :heading], 1]], seen
    store.set(:value, 2)
    assert_equal 1, seen.length
    store.set(:name, "test")
    assert_equal [[:heading], 2], seen.last
  end

  def test_batched_changes_notify_once
    store = Carbn::Store.new(@graph)
    seen = []
    store.subscribe { |regions, revision| seen << [regions, revision] }
    store.transaction do
      store.set(:value, 5)
      store.transaction { store.set(:name, "next") }
    end
    assert_equal "next: 10", store.get(:label)
    assert_equal 1, store.revision
    assert_equal 1, seen.length
  end

  def test_failed_derivation_rolls_back
    graph = Carbn::Graph.define do
      state :x, initial: 1
      derive(:inverse, from: [:x]) { |x| 10 / x }
      region :output, depends_on: [:inverse]
    end
    store = Carbn::Store.new(graph)
    assert_raises(ZeroDivisionError) { store.set(:x, 0) }
    assert_equal 1, store.get(:x)
    assert_equal 0, store.revision
  end

  def test_rejects_cycles_unknown_and_duplicates
    assert_raises(Carbn::DefinitionError) do
      Carbn::Graph.define do
        derive(:a, from: [:b]) { |b| b }
        derive(:b, from: [:a]) { |a| a }
      end
    end
    assert_raises(Carbn::UnknownSignal) { Carbn::Graph.define { region :bad, depends_on: [:missing] } }
    assert_raises(Carbn::DefinitionError) { Carbn::Graph.define { state :a, initial: 1; state :a, initial: 2 } }
  end

  def test_independent_non_diesl_presenter
    store = Carbn::Store.new(@graph)
    renderer = Object.new
    def renderer.render(component) = "<b>#{component}</b>"
    presenter = Carbn::Presenter.new(store: store, renderer: renderer, regions: {
      counter: ->(state) { state.fetch(:double) },
      heading: ->(state) { state.fetch(:label) }
    })
    updates = []
    presenter.subscribe { |regions, revision| updates << [regions, revision] }
    store.set(:name, "hello")
    assert_equal [{heading: "<b>hello: 2</b>"}, 1], updates.last
  end

  def test_unsubscribe
    store = Carbn::Store.new(@graph)
    notifications = []
    unsubscribe = store.subscribe { |regions, _| notifications << regions }
    unsubscribe.call
    store.set(:value, 3)
    assert_empty notifications
  end
end

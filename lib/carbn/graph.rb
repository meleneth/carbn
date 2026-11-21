# frozen_string_literal: true

module Carbn
  class DefinitionError < StandardError; end
  class UnknownSignal < DefinitionError; end

  # Immutable graph of declared states, derivations and rendered regions.
  class Graph
    Derivation = Struct.new(:name, :dependencies, :compute, keyword_init: true)
    Region = Struct.new(:name, :dependencies, keyword_init: true)

    attr_reader :initial, :derivations, :regions, :order

    def self.define(&block)
      builder = Builder.new
      builder.instance_eval(&block)
      builder.build
    end

    def initialize(initial:, derivations:, regions:, order:)
      @initial = initial.freeze
      @derivations = derivations.freeze
      @regions = regions.freeze
      @order = order.freeze
      freeze
    end

    def affected(changes)
      dirty = changes.map(&:to_sym)
      order.each do |name|
        dirty << name if (derivations.fetch(name).dependencies.any? { |dep| dirty.include?(dep) }
      end
      regions.values.select { |region| region.dependencies.any? { |dep| dirty.include?(dep) } }.map(&:name)
    end

    class Builder
      def initialize
        @initial = {}
        @derivations = {}
        @regions = {}
      end

      def state(name, initial:)
        name = name.to_sym
        raise DefinitionError, "Duplicate signal #{name}" if @initial.key?(name) || @derivations.key?(name)
        @initial[name] = initial
      end

      def derive(name, from:, &compute)
        name = name.to_sym
        raise DefinitionError, "Duplicate signal #{name}" if @initial.key?(name) || @derivations.key?(name)
        raise DefinitionError, "Derivation #{name} needs a block" unless compute
        @derivations[name] = Derivation.new(name: name, dependencies: Array(from).map(&:to_sym).freeze, compute: compute).freeze
      end

      def region(name, depends_on:)
        name = name.to_sym
        raise DefinitionError, "Duplicate region #{name}" if @regions.key?(name)
        @regions[name] = Region.new(name: name, dependencies: Array(depends_on).map(&:to_sym).freeze).freeze
      end

      def build
        signals = @initial.keys + @derivations.keys
        (@derivations.values + @regions.values).each do |entry|
          entry.dependencies.each do |dep|
            raise UnknownSignal, "Unknown dependency #{dep} for #{entry.name}" unless signals.include?(dep)
          end
        end
        marks = {}
        order = []
        visit = lambda do |name|
          case marks[name]
          when :done then return
          when :visiting then raise DefinitionError, "Dependency cycle at #{name}"
          end
          marks[name] = :visiting
          @derivations.fetch(name).dependencies.each { |dep| visit.call(dep) if @derivations.key?(dep) }
          marks[name] = :done
          order << name
        end
        @derivations.each_key { |name| visit.call(name) }
        Graph.new(initial: @initial.dup, derivations: @derivations.dup, regions: @regions.dup, order: order)
      end
    end
  end
end

# frozen_string_literal: true

module Carbn
  # Synchronous, transactional reactive state without browser or Rails dependencies.
  class Store
    attr_reader :graph, :revision

    def initialize(graph)
      @graph = graph
      @values = graph.initial.dup
      @revision = 0
      @observers = []
      @transaction_depth = 0
      @pending = {}
      recalculate!(@values)
    end

    def get(name)
      # Read-your-writes, including derived projections, inside a transaction.
      values = if @transaction_depth.positive? && !@pending.empty?
                 proposed = @values.merge(@pending)
                 recalculate!(proposed)
                 proposed
               else
                 @values
               end
      values.fetch(name.to_sym) { raise UnknownSignal, "Unknown signal #{name}" }
    end

    def snapshot
      @values.dup.freeze
    end

    def subscribe(&listener)
      raise ArgumentError, "Subscriber must be callable" unless listener
      @observers << listener
      -> { @observers.delete(listener) }
    end

    def set(name, value)
      raise DefinitionError, "Cannot assign derived signal #{name}" if graph.derivations.key?(name.to_sym)
      raise UnknownSignal, "Unknown signal #{name}" unless graph.initial.key?(name.to_sym)
      transaction { @pending[name.to_sym] = value }
      value
    end

    def transaction
      if @transaction_depth.positive?
        @transaction_depth += 1
        begin
          return yield(self)
        ensure
          @transaction_depth -= 1
        end
      end
      @transaction_depth = 1
      @pending = {}
      begin
        result = yield(self)
        changed = @pending.select { |name, value| @values[name] != value }
        unless changed.empty?
          proposed = @values.merge(@pending)
          recalculate!(proposed)
          dirty = changed.keys + graph.order.select { |name| @values[name] != proposed[name] }
          @values = proposed
          @revision += 1
          regions = graph.regions.values.select { |region| region.dependencies.any? { |dep| dirty.include?(dep) } }.map(&:name).freeze
          @observers.dup.each { |observer| observer.call(regions, @revision) } unless regions.empty?
        end
        result
      ensure
        @pending = {}
        @transaction_depth = 0
      end
    end

    private

    def recalculate!(values)
      graph.order.each do |name|
        definition = graph.derivations.fetch(name)
        values[name] = definition.compute.call(*definition.dependencies.map { |dep| values.fetch(dep) })
      end
    end
  end
end

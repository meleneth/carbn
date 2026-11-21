# frozen_string_literal: true

module Carbn
  # Application supplies component factories. Renderer supplies HTML.
  class Presenter
    def initialize(store:, renderer:, regions:)
      @store = store
      @renderer = renderer
      @regions = regions.transform_keys(&:to_sym)
      unknown = @regions.keys - store.graph.regions.keys
      raise DefinitionError, "Unknown render regions: #{unknown.inspect}" unless unknown.empty?
    end

    def render(affected = @regions.keys)
      affected.to_h do |name|
        factory = @regions.fetch(name.to_sym)
        [name.to_sym, @renderer.render(factory.call(@store.snapshot))]
      end
    end

    def subscribe(&consumer)
      @store.subscribe do |regions, revision|
        updates = render(regions & @regions.keys)
        consumer.call(updates, revision) unless updates.empty?
      end
    end
  end

  # Only this optional adapter loads ViewComponent and ActionView.
  class ViewComponentRenderer
    def initialize(context: nil)
      require "view_component"
      require "action_view"
      @context = context || ActionView::Base.empty
    end

    def render(component)
      unless defined?(ViewComponent::Base) && component.is_a?(ViewComponent::Base)
        raise ArgumentError, "Expected a ViewComponent::Base instance"
      end
      component.render_in(@context)
    end
  end
end

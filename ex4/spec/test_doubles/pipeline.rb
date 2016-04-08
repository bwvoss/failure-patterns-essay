require 'boundary'

module TestDoubles
  class Pipeline
    extend Boundary

    def blow_up
      raise
    end

    def custom_blow_up
      raise
    end

    def add_1(number)
      number + 1
    end

    def add_2(number)
      number + 2
    end

    def times_3(number)
      number * 3
    end

    protect! [
      { method_name: :custom_blow_up, i18n: :custom },
      { method_name: :custom_blow_up, i18n: :extra, extra: lambda { |data, error| data == {} } }
    ]
  end
end

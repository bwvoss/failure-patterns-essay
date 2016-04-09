module TestDoubles
  class ErrorHandler
    class << self
      def blow_up(data, error)
        :default
      end

      def custom_blow_up(data, error)
        if data == {}
          :extra
        else
          :custom
        end
      end

      def default(data, error)
        :default
      end
    end
  end
end

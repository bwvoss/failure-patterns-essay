require 'error_handler'
require 'logger'

module Boundary
  def protect!(on_error_config = [])
    methods = instance_methods - Object.instance_methods
    error_handler = ErrorHandler.new(on_error_config)

    define_method("final") do |*args, &block|
      return @final_value
    end

    methods.each do |method|
      define_method("protected_#{method}") do
        return self if @failed

        begin
          @result = __send__("original_#{method}", @result)
          @final_value = [@result, nil]
        rescue => e
          @failed = true
          error = error_handler.error_for(e, method, @result)
          Logger.error(error.system_error_information)

          @final_value = [nil, error.user_error_information]
        end

        self
      end

      alias_method "original_#{method}", method
      alias_method method, "protected_#{method}"
    end
  end
end

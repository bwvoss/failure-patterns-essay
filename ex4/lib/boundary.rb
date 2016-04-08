require 'error_handler'
require 'logger'

module Boundary
  def protect!
    methods = instance_methods - Object.instance_methods

    define_method("initialize") do |value|
      @result = value
    end

    #if success, return value, otherwise, delgate to handler
    #blow up if method doesn't exist on self that we are sending to
    #the handler
    define_method("on_error") do |handler|
      [@result, handler.__send__(@method, @result, @error)]
    end

    methods.each do |method|
      define_method("protected_#{method}") do
        return self if @failed

        begin
          @result = __send__("original_#{method}", @result)
        rescue => e
          @failed = true
          @error = e
          @method = method
        end

        self
      end

      alias_method "original_#{method}", method
      alias_method method, "protected_#{method}"
    end
  end
end

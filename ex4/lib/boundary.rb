module Boundary
  def protect!
    methods = instance_methods - Object.instance_methods

    define_method("initialize") do |value|
      @result = value
    end

    define_method("on_error") do |handler|
      err =
        if @method && handler.respond_to?(@method)
          handler.__send__(@method, @result, @error)
        elsif @method
          handler.__send__(:default, @result, @error)
        end

      [@result, err]
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

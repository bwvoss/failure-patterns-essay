require 'logger'

module Boundary
  def self.included(klass)
    imethods = klass.instance_methods(false)

    klass.send(:define_method, "initialize") do |value|
      @result = value
      super()
    end

    klass.send(:define_method, "on_error") do |handler|
      err =
        if @method && handler.respond_to?(@method)
          handler.__send__(@method, @result, @error)
        elsif @method
          handler.__send__(:default, @result, @error)
        end

      Logger.error(err) if err

      [@result, err]
    end

    imethods.each do |method|
      klass.send(:define_method, "protected_#{method}") do
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

      klass.send(:alias_method, "original_#{method}", method)
      klass.send(:alias_method, method, "protected_#{method}")
    end
  end
end

require 'error'

class ErrorHandler
  DEFAULT_CONFIG = { i18n: :default }

  def initialize(config)
    @config = config
  end

  def error_for(e, method, result)
    i18n = i18n_for(e, method, result)
    Error.new(e, i18n)
  end

  private

  def i18n_for(e, method, result)
    extra_config = extra_for(e, method, result)

    if extra_config
      return extra_config[:i18n]
    else
      default_for(method)
    end
  end

  def extra_for(e, method, result)
    extras = @config.select do |c|
      c[:method_name] == method && c[:extra]
    end

    if extras
      extras.find do |c|
        c[:extra].call(result, e)
      end
    end
  end

  def default_for(method)
    @config.find(lambda { DEFAULT_CONFIG }) do |c|
      c[:method_name] == method && !c[:extra]
    end[:i18n]
  end
end

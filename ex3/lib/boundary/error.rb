require 'pretty_backtrace'
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

module Boundary
  class Error < RuntimeError
    attr_reader :error

    def initialize(error, error_configs)
      @error = error
      @error_configs = error_configs
    end

    def default_error_config
      { i18n: :default }
    end

    def system_error_information
      error.backtrace[0...5]
    end

    def user_error_information
      i18n
    end

    private

    def i18n
      backtrace = error.backtrace[0...5].join(',')

      @error_configs.find(lambda{ default_error_config }) do |c|
        backtrace.include?(c[:matcher])
      end[:i18n]
    end
  end
end

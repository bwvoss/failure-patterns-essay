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
      { eid: :default }
    end

    def system_error_information
      error.backtrace[0...5]
    end

    def user_error_information
      eid
    end

    private

    def eid
      backtrace = error.backtrace[0...5].join(',')

      @error_configs.find(lambda{ default_error_config }) do |c|
        backtrace.include?(c[:matcher])
      end[:eid]
    end
  end
end

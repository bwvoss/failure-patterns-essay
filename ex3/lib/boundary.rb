require 'pretty_backtrace'
PrettyBacktrace.enable

module Boundary
  def self.call
    begin
      [yield, nil]
    rescue => e
      error = Error.new(e)
      Logger.error(error.system_error_information)

      [nil, error.user_error_information]
    end
  end

  class Error < RuntimeError
    attr_reader :error

    def initialize(error)
      @error = error
    end

    def error_configs
      [{ method: 'format_date', eid: :invalid_date }]
    end

    def system_error_information
      error.backtrace[0..4]
    end

    def user_error_information
      backtrace = error.backtrace.first

      error_configs.find(lambda{ {eid: :default} }) do |c|
        backtrace.include?(c[:method])
      end[:eid]
    end
  end

  class Logger
    def self.error(info)
    end
  end
end

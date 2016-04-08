require 'logger'
require 'pretty_backtrace'
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

class Error
  attr_reader :i18n

  def initialize(error, i18n)
    @error = error
    @i18n = i18n
    log
  end

  private

  def log
    Logger.error(system_error_information)
  end

  def system_error_information
    {
      error: @error.inspect,
      backtrace: @error.backtrace[0...5],
      i18n: @i18n
    }
  end

  def user_error_information
    @i18n
  end
end

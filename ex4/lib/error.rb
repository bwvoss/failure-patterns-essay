require 'pretty_backtrace'
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

class Error
  attr_reader :error

  def initialize(error, eid)
    @error = error
    @eid = eid
  end

  def system_error_information
    error.backtrace[0...5]
  end

  def user_error_information
    @eid
  end
end

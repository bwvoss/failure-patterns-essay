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
    { error: @error.inspect, backtrace: error.backtrace[0...5], eid: @eid }
  end

  def user_error_information
    @eid
  end
end

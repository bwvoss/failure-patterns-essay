require 'error'

class ErrorHandler
  def initialize(config)
    @config = config
  end

  def default_error_config
    { eid: :default }
  end

  def error_for(e, action)
    eid = eid_for(e, action)
    Error.new(e, eid)
  end

  private

  def eid_for(e, action)
    @config.find(lambda { default_error_config } ) do |c|
      c[:action] == action
    end[:eid]
  end
end

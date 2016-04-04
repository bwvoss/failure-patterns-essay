require 'boundary/error'
require 'boundary/logger'

module Boundary
  def self.run(error_configuration = [])
    begin
      [yield, nil]
    rescue => e
      error = Error.new(e, error_configuration)
      Logger.error(error.system_error_information)

      [nil, error.user_error_information]
    end
  end
end

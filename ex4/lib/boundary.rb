require 'boundary_error'
require 'logger'

class Boundary
  def initialize(pipeline, data, error_configuration)
    @pipeline = pipeline
    @data = data
    @error_config = error_config
  end

  def run
    begin
      result = @pipeline.reduce(@data) do |data, action|
        @action = action
        action.call(data)
      end

      [result, nil]
    rescue => e
      error = @error_config.error_for(e, @action)
      Logger.error(error.system_error_information)

      [nil, error.user_error_information]
    end
  end
end

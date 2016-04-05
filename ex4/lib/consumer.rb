require 'boundary'
require 'error_handler'
require 'rescuetime/pipeline'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error = Boundary.new(
      Rescuetime::Pipeline,
      datetime,
      ErrorHandler.new(error_config)
    ).run
  end

  private

  def error_config
    [
      { matcher: 'FormatDate', eid: :invalid_date },
      { action: 'FetchRows', qualifier: lambda { |e| e.inspect == "# key is invalid" }, eid: :invalid_api_key }
    ]
  end
end

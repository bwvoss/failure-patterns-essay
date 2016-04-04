require 'boundary'
require 'rescuetime/fetch'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error = Boundary.run(error_config) do
      Rescuetime::Fetch.call(datetime)
    end
  end

  private

  def error_config
    [
      { matcher: '# key not found', eid: :invalid_api_key },
      { matcher: 'format_date', eid: :invalid_date }
    ]
  end
end

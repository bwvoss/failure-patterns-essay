require 'boundary'
require 'rescuetime/fetch'
require 'rescuetime/error_configuration'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error = Boundary.run(Rescuetime::ErrorConfiguration) do
      Rescuetime::Fetch.call(datetime)
    end
  end
end

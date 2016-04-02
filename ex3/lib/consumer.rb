require 'boundary'
require 'fetch_rescuetime_data'

module Consumer
  def get(datetime)
    result, error = Boundary.call { RescuetimeData.fetch(datetime) }
  end
end

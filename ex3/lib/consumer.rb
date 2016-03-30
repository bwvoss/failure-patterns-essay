require 'boundary'
require 'fetch_rescuetime_data'

module Consumer
  def get
    result, error = Boundary.call do
      RescuetimeData.fetch
    end
  end
end

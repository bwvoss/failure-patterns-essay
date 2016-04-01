require 'boundary'
require 'fetch_rescuetime_data'

module Consumer
  def get
    result, error = Boundary.call do
      RescuetimeData.fetch
    end
    # either raise error, or just return it and have the web handle it
  end
end

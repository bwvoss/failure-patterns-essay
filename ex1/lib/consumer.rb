require 'fetch_rescuetime_data'

module Consumer
  def get
    RescuetimeData.fetch(params[:datetime])
  end
end

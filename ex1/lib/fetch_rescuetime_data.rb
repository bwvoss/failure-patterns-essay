require 'active_support/core_ext/time/calculations.rb'

class RescuetimeData
  def self.fetch(datetime)
    formatted_date = datetime.strftime('%Y-%m-%d')
    url =
      "#{ENV['RESCUETIME_API_URL']}?"\
      "key=#{ENV['RESCUETIME_API_KEY']}&"\
      "restrict_begin=#{formatted_date}&"\
      "restrict_end=#{formatted_date}&"\
      'perspective=interval&'\
      'resolution_time=minute&'\
      'format=json'

    response = HTTParty.get(url)

    parsed_rows = response.fetch('rows').map do |row|
      {
        date:                  ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
        time_spent_in_seconds: row[1],
        number_of_people:      row[2],
        activity:              row[3],
        category:              row[4],
        productivity:          row[5]
      }
    end
  end
end

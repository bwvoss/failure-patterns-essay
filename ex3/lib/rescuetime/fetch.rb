require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'

module Rescuetime
  class Fetch
    def self.call(datetime)
      formatted_date = format_date(datetime)

      response = request(formatted_date)

      response.fetch('rows').map do |row|
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

    def self.format_date(datetime)
      Time.parse(datetime).strftime('%Y-%m-%d')
    end

    def self.request(datetime)
      url =
        "#{ENV['RESCUETIME_API_URL']}?"\
        "key=#{ENV['RESCUETIME_API_KEY']}&"\
      "restrict_begin=#{datetime}&"\
      "restrict_end=#{datetime}&"\
      'perspective=interval&'\
        'resolution_time=minute&'\
        'format=json'

      HTTParty.get(url)
    end
  end
end

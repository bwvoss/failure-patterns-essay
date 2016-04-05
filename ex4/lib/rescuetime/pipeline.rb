require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'

module Rescuetime
  Pipeline = [
    FormatDate,
    BuildUrl,
    Request,
    FetchRows,
    ParseRows
  ]

  class FormatDate
    def self.call(datetime)
      Time.parse(datetime).strftime('%Y-%m-%d')
    end
  end

  class BuildUrl
    def self.call(datetime)
      "#{ENV.fetch('RESCUETIME_API_URL')}?"\
      "key=#{ENV.fetch('RESCUETIME_API_KEY')}&"\
      "restrict_begin=#{datetime}&"\
      "restrict_end=#{datetime}&"\
      'perspective=interval&'\
      'resolution_time=minute&'\
      'format=json'
    end
  end

  class Request
    def self.call(url)
      HTTParty.get(url)
    end
  end

  class FetchRows
    def self.call(response)
      response.fetch('rows')
    end
  end

  class ParseRows
    def self.call(rows)
      timezone = ENV.fetch('RESCUETIME_TIMEZONE')
      rows.map do |row|
        {
          date:                  ActiveSupport::TimeZone[timezone].parse(row[0]).utc.to_s,
          time_spent_in_seconds: row[1],
          number_of_people:      row[2],
          activity:              row[3],
          category:              row[4],
          productivity:          row[5]
        }
      end
    end
  end
end

require 'active_support/core_ext/time/calculations.rb'

class RescuetimeData
  def self.fetch(datetime)
    run_start_time = Time.now

    begin
      build_url(datetime)
    rescue => e
      Log.fatal("Unparsable date of: #{e.inspect}")
    end

    start_time = Time.now
    begin
      response = HTTParty.get(url)
    rescue => e
      Log.fatal("Http failed: #{e.inspect}, with url of #{url}")
    end

    Log.info("duration of http request: #{Time.now - start_time}")

    start_time = Time.now
    begin
      parsed_rows = parse_response_to_rows(response)
    rescue => e
      Log.fatal("parsing of date to utc failed: #{e.inspect}")
    end

    Log.info("duration of data parsing: #{Time.now - start_time}")
    Log.info("Rescuetime fetch completed in: #{Time.now - run_start_time}")

    parsed_rows
  end

  def self.build_url(datetime)
    formatted_date = datetime.strftime('%Y-%m-%d')

    "#{ENV['RESCUETIME_API_URL']}?"\
    "key=#{ENV['RESCUETIME_API_KEY']}&"\
    "restrict_begin=#{formatted_date}&"\
    "restrict_end=#{formatted_date}&"\
    'perspective=interval&'\
    'resolution_time=minute&'\
    'format=json'
  end

  def self.parse_response_to_rows(response)
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
end

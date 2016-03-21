require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime, logger)
    run_start_time = Time.now

    begin
      url = build_url(datetime)
    rescue => e
      logger.fatal("Problem parsing url: #{e.inspect}")
			return
    end

    start_time = Time.now
    begin
      response = HTTParty.get(url)
    rescue => e
      logger.fatal("Http failed: #{e.inspect}")
			return
    end

    logger.info("duration of http request: #{Time.now - start_time}")

    start_time = Time.now
    begin
      parsed_rows = parse_response_to_rows(response)
    rescue => e
      logger.fatal("Parsing date failed: #{e.inspect}")
    end

    logger.info("duration of data parsing: #{Time.now - start_time}")
    logger.info("Rescuetime fetch completed in: #{Time.now - run_start_time}")

    parsed_rows
  end

  def self.build_url(datetime)
		raise if datetime.nil?
    formatted_date = datetime.strftime('%Y-%m-%d')

		api_url = ENV['RESCUETIME_API_URL']
		api_key = ENV['RESCUETIME_API_KEY']
		raise if api_url.nil? || api_key.nil?

    "#{api_url}?"\
    "key=#{api_key}&"\
    "restrict_begin=#{formatted_date}&"\
    "restrict_end=#{formatted_date}&"\
    'perspective=interval&'\
    'resolution_time=minute&'\
    'format=json'
  end

  def self.parse_response_to_rows(response)
		timezone = ENV['RESCUETIME_TIMEZONE']
		raise "no timezone" if timezone.nil?

    response.fetch('rows').map do |row|
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

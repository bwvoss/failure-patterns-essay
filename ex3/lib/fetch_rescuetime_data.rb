require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class ChocolateShell
  # with chocolate rain
  def self.call(actions, context)
    actions.reduce(context) do |context, action|
      begin
        action.call(context)
      rescue => e
        # Forces me to make the log more generic
        # but cleans the exception handling and fatal logging
        context.fetch(:logger).fatal("action: #{action} failed with: #{e.inspect}")
        # break from the loop and handle error gracefully
        break
      end
    end

    context
  end
end

class RescuetimeData
  def self.fetch(datetime, logger)
    actions = [
      -> (context) { self.build_url(context) },
      -> (context) { self.make_get_request(context) },
      -> (context) { self.parse_response_to_rows(context) }
    ]

    run_start_time = Time.now
    context = ChocolateShell.call(actions, datetime: datetime, logger: logger)

    logger.info("Rescuetime fetch completed in: #{Time.now - run_start_time}")

    context.fetch(:parsed_rows)
  end

  def self.build_url(context)
    datetime = context.fetch(:datetime)
    formatted_date = datetime.strftime('%Y-%m-%d')

    context[:url] = "#{ENV['RESCUETIME_API_URL']}?"\
    "key=#{ENV['RESCUETIME_API_KEY']}&"\
    "restrict_begin=#{formatted_date}&"\
    "restrict_end=#{formatted_date}&"\
    'perspective=interval&'\
    'resolution_time=minute&'\
    'format=json'

    context
  end

  def self.make_get_request(context)
    start_time = Time.now

    context[:response] = HTTParty.get(context.fetch(:url))

    context.fetch(:logger).info("duration of http request: #{Time.now - start_time}")

    context
  end

  def self.parse_response_to_rows(context)
    start_time = Time.now

    parsed_rows = context.fetch(:response).fetch('rows').map do |row|
      {
        date:                  ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
        time_spent_in_seconds: row[1],
        number_of_people:      row[2],
        activity:              row[3],
        category:              row[4],
        productivity:          row[5]
      }
    end

    context[:parsed_rows] = parsed_rows

    context.fetch(:logger).info("duration of data parsing: #{Time.now - start_time}")

    context
  end
end

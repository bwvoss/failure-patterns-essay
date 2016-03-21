require 'fetch_rescuetime_data'

module TestDouble
  class Logger
    attr_reader :fatal_messages, :info_messages

    def initialize
      @fatal_messages = []
      @info_messages = []
    end

    def fatal(message)
      @fatal_messages << message
    end

    def info(message)
      @info_messages << message
    end
  end
end

describe RescuetimeData do
  it 'fetches resucetime data and returns the parsed rows' do
    ENV['RESCUETIME_TIMEZONE'] = 'America/Chicago'
    ENV['RESCUETIME_API_URL'] = 'http://localhost:8080'
    ENV['RESCUETIME_API_KEY'] = 'secret123'

    datetime = Time.parse('2015/01/22')

    expected_url =
      "http://localhost:8080?"\
      "key=secret123&"\
      "restrict_begin=2015-01-22&"\
      "restrict_end=2015-01-22&"\
      'perspective=interval&'\
      'resolution_time=minute&'\
      'format=json'

    date = Time.now
    expect(HTTParty).to receive(:get).with(expected_url) do
      {
        'rows' => [
          [date.to_s, 1, 3, 'bowling', 'entertainment', 0]
        ]
      }
    end

    results = described_class.fetch(datetime, TestDouble::Logger.new)

    expect(results.count).to eq(1)
    expect(results.first).to include({
      time_spent_in_seconds: 1,
      number_of_people: 3,
      activity: 'bowling',
      category: 'entertainment',
      productivity: 0
    })
    expect(Time.parse(results.first[:date])).to be_utc
  end
end

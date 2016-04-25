require 'fetch_rescuetime_data'

describe RescuetimeData do
  it 'fetches resucetime data and returns the parsed rows' do
    ENV['RESCUETIME_TIMEZONE'] = 'America/Chicago'
    ENV['RESCUETIME_API_URL'] = 'http://localhost:8080'
    ENV['RESCUETIME_API_KEY'] = 'secret123'

    datetime = '2015-01-22'

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

    results = described_class.fetch(datetime)

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

  context 'failures' do
    let(:datetime) { '2015-01-22' }

    context 'url errors' do
      it 'handles invalid datetimes' do
        result = described_class.fetch(nil)

        expect(result).to eq({:error=>"not a real date"})
      end

      it 'handles missing api url env var and returns' do
        ENV['RESCUETIME_API_URL'] = nil
        result = described_class.fetch(datetime)

        expect(result).to be_nil
      end

      it 'handles missing api key env var and returns' do
        ENV['RESCUETIME_API_KEY'] = nil
        result = described_class.fetch(datetime)

        expect(result).to be_nil
      end
    end

    it 'handles timezone not present errors and returns' do
      ENV['RESCUETIME_TIMEZONE'] = nil
      expect(HTTParty).to receive(:get)
      result = described_class.fetch(datetime)

      expect(result).to be_nil
    end
  end
end

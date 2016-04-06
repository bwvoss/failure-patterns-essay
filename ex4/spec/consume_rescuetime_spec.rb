require 'consumer'

describe 'Consuming Rescuetime' do
  let(:consumer) { Consumer.new }

  context 'user specific feedback' do
    it 'returns i18n for date invalid errors' do
      consumer.get('not-a-date')

      expect(consumer.error).to eq(:invalid_date)
    end

    it 'returns i18n for invalid api key' do
      expect(HTTParty).to receive(:get) do
        {
          error: '# key not found',
          messages: 'key not found'
        }
      end
      ENV['RESCUETIME_API_URL'] = 'http://someapi.com'
      ENV['RESCUETIME_API_KEY'] = '8sdnjf7sdnf0'

      consumer.get('2015-10-10')

      expect(consumer.error).to eq(:invalid_api_key)
    end

    it 'returns default if no rows' do
      expect(HTTParty).to receive(:get) { {} }
      ENV['RESCUETIME_API_URL'] = 'http://someapi.com'
      ENV['RESCUETIME_API_KEY'] = '8sdnjf7sdnf0'

      consumer.get('2015-10-10')

      expect(consumer.error).to eq(:default)
    end
  end
end

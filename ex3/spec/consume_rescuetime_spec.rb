require 'consumer'

describe 'Consuming Rescuetime' do
  let(:consumer) { Consumer.new }

  context 'user specific feedback' do
    it 'returns eid for date invalid errors' do
      consumer.get('not-a-date')

      expect(consumer.error).to eq(:invalid_date)
    end

    it 'returns eid for invalid api key' do
      expect(HTTParty).to receive(:get) do
        {
          error: '# key not found',
          messages: 'key not found'
        }
      end

      consumer.get('2015-10-10')

      expect(consumer.error).to eq(:invalid_api_key)
    end
  end
end

require 'boundary'
require 'fetch_rescuetime_data'

describe Boundary do
  it 'returns the generic error' do
    result, error = described_class.call { 5/0 }

    expect(error).to eq(:default)
  end

  it 'returns the result' do
    result, error = described_class.call { 1 + 1 }

    expect(result).to eq(2)
  end

  context 'RescuetimeData specific feedback' do
    it 'returns a different result for date invalid errors' do
      result, error = described_class.call { RescuetimeData.fetch('not-a-date') }

      expect(error).to eq(:invalid_date)
    end
  end
end

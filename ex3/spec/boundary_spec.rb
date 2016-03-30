require 'boundary'

describe Boundary do
  it 'returns the error' do
    result, error = described_class.call { 5/0 }

    expect(error).to be_kind_of(Boundary::Error)
  end
end

require 'boundary'

describe Boundary do
  it 'returns the generic error' do
    result, error = described_class.run { 5/0 }

    expect(error).to eq(:default)
  end

  it 'returns the generic error with custom config' do
    error_config = [{ matcher: 'something', i18n: :test}]
    result, error = described_class.run { 5/0 }

    expect(error).to eq(:default)
  end

  it 'returns the result' do
    result, error = described_class.run { 1 + 1 }

    expect(result).to eq(2)
  end

  it 'returns the specific error' do
    error_config = [{ matcher: 'divided by 0', i18n: :bad_math }]

    result, error = described_class.run(error_config) do
      5/0
    end

    expect(error).to eq(:bad_math)
  end
end

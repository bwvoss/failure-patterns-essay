require 'boundary'
require 'test_doubles/pipeline'

describe Boundary do
  let(:test_pipeline) do
    TestDoubles::Pipeline.new(1)
  end

  it 'returns an error' do
    result, error = test_pipeline
      .blow_up
      .final

    expect(error).to eq(:default)
  end

  it 'returns an custom i18n key' do
    result, error = test_pipeline
      .custom_blow_up
      .final

    expect(error).to eq(:custom)
  end

  it 'returns an custom i18n key found with extra data' do
    result, error = TestDoubles::Pipeline.new({})
      .custom_blow_up
      .final

    expect(error).to eq(:extra)
  end

  it 'logs data on error' do
    expect(Logger).to receive(:error)

    test_pipeline.blow_up.final
  end

  it 'returns a result' do
    result, error = test_pipeline.add_1.final

    expect(result).to eq(2)
  end

  it 'method chains' do
    result, error = test_pipeline
      .add_1
      .add_2
      .times_3
      .final

    expect(result).to eq(12)
  end
end

require 'boundary'
require 'test_doubles/pipeline'
require 'test_doubles/error_handler'

describe Boundary do
  let(:test_pipeline) do
    TestDoubles::Pipeline.new(1)
  end

  let(:error_handler) { TestDoubles::ErrorHandler }

  xit 'accepts a pre condition' do
  end

  xit 'returns a Boundary::PreConditionError if pre-condition fails' do
  end

  xit 'builds a log' do
  end

  xit 'error handler implements default by itself, returns BoundaryHandler::DefaultError with callstack' do
  end

  it 'returns an error' do
    result, error = test_pipeline
      .blow_up
      .on_error(error_handler)

    expect(error).to eq(:default)
  end

  it 'returns an custom key' do
    result, error = test_pipeline
      .custom_blow_up
      .on_error(error_handler)

    expect(error).to eq(:custom)
  end

  it 'returns an custom i18n key found with extra data' do
    result, error = TestDoubles::Pipeline.new({})
      .custom_blow_up
      .on_error(error_handler)

    expect(error).to eq(:extra)
  end

  it 'calls default if the method is not defined on the handler' do
    result, error = test_pipeline
      .not_handled
      .on_error(error_handler)

    expect(error).to eq(:default)
  end

  it 'returns a result' do
    result, error = test_pipeline
      .add_1
      .on_error(error_handler)

    expect(result).to eq(2)
  end

  it 'method chains' do
    result, error = test_pipeline
      .add_1
      .add_2
      .times_3
      .on_error(error_handler)

    expect(result).to eq(12)
  end
end

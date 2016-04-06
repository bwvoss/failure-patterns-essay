require 'boundary/error'

describe Boundary::Error do
  context 'developer specific feedback' do
    it 'has a detailed backtrace'
    it 'has the error'
  end

  context 'user specific error' do
    it 'returns an i18n key'
  end
end

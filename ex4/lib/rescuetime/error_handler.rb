require 'error'

module Rescuetime
  class ErrorHandler
    def format_date(data, error)
      Error.new(error, :invalid_date).log
    end

    def fetch_rows(data, error)
      if data[:error] == "# key not found"
        Error.new(error, :invalid_api_key).log
      else
        default(data, error)
      end
    end

    def default(data, error)
      Error.new(error, :default).log
    end
  end
end

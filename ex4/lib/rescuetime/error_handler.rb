module Rescuetime
  class ErrorHandler
    def format_date(data, error)
      Error.new(error, :invalid_date)
    end

    def fetch_rows(data, error)
      if data[:error] == "# key not found"
        Error.new(error, :invalid_api_key)
      end
    end

    def default(data, error)
      :default
    end
  end
end

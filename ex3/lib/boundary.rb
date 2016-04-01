module Boundary
  def self.call
    begin
      [yield, nil]
    rescue => e
      [nil, Error.new(e.name)]
    end
  end

  class Error < RuntimeError
    attr_reader :backtrace

    def initialize(name)
      @backtrace = caller
    end
  end
end

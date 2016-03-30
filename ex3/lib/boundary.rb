module Boundary
  def self.call
    yield
  rescue => e
    p caller
  end
end

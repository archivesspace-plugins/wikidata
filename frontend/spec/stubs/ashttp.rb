module ASHTTP
  def self.start_uri(*args, &block)
    raise "ASHTTP.start_uri should not be called in unit tests"
  end
end

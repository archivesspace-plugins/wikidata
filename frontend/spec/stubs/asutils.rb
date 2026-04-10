require 'tempfile'
module ASUtils
  def self.tempfile(prefix)
    Tempfile.new(prefix)
  end
end

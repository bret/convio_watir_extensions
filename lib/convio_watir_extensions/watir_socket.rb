require 'socket'
require 'watir/ie'
require 'timeout'

# modal lock
# 1. try changing the installed watir package to make sure this is really being used
# 2. try logging the thread activity

# registration
# Need to track who is using so if multiple watir threads don't get
# an unexpected shutdown when one leaves

# Spin our own version of watir to avoid needing to include this
module Watir
  class IE
    def _attach_init how, what
      attach_browser_window how, what
      initialize_options
      #wait
    end
  end
end

begin
  dts = TCPServer.new('localhost', 20000)  
  loop do  
    Thread.start(dts.accept) do |s|
      request = s.read
      #print(s, request) 
      Thread.new { eval(request) }
      s.close  
    end  
  end
rescue Errno::EADDRINUSE
  # exit gracefully - someone has already started the server
end

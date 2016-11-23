require 'faraday'
require 'mdk'

require 'faraday_mdk'

mdk = ::Quark::Mdk.start
session = mdk.session
session.setDeadline(1.0)
conn = Faraday.new(:url => ARGV[0]) do |faraday|
  faraday.request :mdk_session, session
  faraday.adapter  Faraday.default_adapter
end
begin
  response = conn.get
  puts "Got: #{response.body}"
rescue Faraday::Error::TimeoutError => err
  exit 123
ensure
  mdk.stop
end

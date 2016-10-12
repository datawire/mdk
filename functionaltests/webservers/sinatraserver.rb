require 'sinatra'
require 'json'
require 'rack-mdk'

use Rack::Lint
use Rack::MDK::Session

set :port, ARGV[0]

get '/context' do
  env[:mdk_session].externalize
end

get '/resolve' do
  session = env[:mdk_session]
  node = session.resolve("service1", "1.0")
  if params['error'] != nil then
    throw "Erroring as requested."
  else
    policy = session._mdk._disco.failurePolicy(node)
    {node.address => [policy.successes, policy.failures]}.to_json
  end
end

get '/timeout' do
  env[:mdk_session].getSecondsToTimeout().to_json
end

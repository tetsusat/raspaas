require 'sinatra'

set :bind, '0.0.0.0'

get '/' do
  container = `hostname` || 'unknown'
  "Hello, world from ${container}"
end
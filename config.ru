require 'rubygems'
require 'bundler'
Bundler.require

load './app.rb'
run Sinatra::Application

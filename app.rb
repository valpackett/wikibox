require 'sinatra'
require 'haml'
require 'sass'
require 'compass'
require 'dropbox'
require 'sequel'
require 'rack-flash'
require 'rack/csrf'
require 'uri'
require 'rdiscount'
require 'redcloth'
require 'org-ruby'

configure do
  enable :sessions
  use Rack::Flash
  use Rack::Csrf, :raise => true
  Compass.configuration do |config|
    config.project_path = File.dirname(__FILE__)
    config.sass_dir = 'views'
  end
  set :public_folder, File.dirname(__FILE__) + '/static'
  set :haml, :format => :html5
  set :sass, Compass.sass_engine_options
end

DB = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://test.db')

class User < Sequel::Model
  plugin :validation_helpers
  def validate
    super
    validates_presence [:email]
  end
end

def wikify(page)
  if page[:text].kind_of? String then
    case page[:name].split('.').last
    when 'md', 'mkd', 'mdown', 'markdown'
      text = markdown(page[:text])
    when 'textile'
      text = textile(page[:text])
    when 'org'
      text = Orgmode::Parser.new(page[:text]).to_html
    else
      text = page[:text]
    end
    text.gsub /\[\[([\s\w.]+)\]\]/ do "<a href='/pages/#{$1}'>#{$1}</a>" end
  else "This page doesn't exist yet." end
end

get '/' do
  if session[:db_session] then
    redirect '/pages'
  else
    haml :landing
  end
end

get '/auth' do
  if params[:oauth_token] then
    db_session = Dropbox::Session.deserialize(session[:db_session])
    db_session.authorize(params)
    session[:db_session] = db_session.serialize
    if not User[:email => db_session.account.email]
      user = User.new
      user[:email] = db_session.account.email
      user.save
      flash[:info] = 'Welcome to Wikibox! Please choose a folder for your wiki.'
      redirect '/settings'
    else
      flash[:info] = 'Welcome back!'
      redirect '/pages'
    end
  else
    db_session = Dropbox::Session.new(ENV['DROPBOX_KEY'], ENV['DROPBOX_SECRET'])
    session[:db_session] = db_session.serialize
    redirect db_session.authorize_url(:oauth_callback => request.url)
  end
end

get '/logout' do
  session[:db_session] = nil
  flash[:info] = 'Good bye!'
  redirect '/'
end

get '/settings' do
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  @user = User[:email => db_session.account.email]
  haml :settings
end

post '/settings' do
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  @user = User[:email => db_session.account.email]
  valid_re = /\A[0-9A-Za-z]+\z/
  if params[:folder] =~ valid_re
    @user[:folder] = params[:folder]
    @user[:indexfile] = params[:indexfile]
    @user.save
    flash[:info] = 'Yay, settings are saved.'
    redirect '/pages'
  else
    flash[:error] = 'Invalid folder name!'
    haml :settings
  end
end

get '/pages' do
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  user = User[:email => db_session.account.email]
  if not user.indexfile then user.indexfile = 'index.md' end
  redirect "/pages/#{user.indexfile}"
end

get '/pages/:page' do |page|
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  @user = User[:email => db_session.account.email]
  if not @user.folder then
    flash[:info] = 'Please specify a folder for your wiki.'
    redirect '/settings'
  end
  db_session.mode=(:dropbox)
  root = db_session.list("/")
  root.each do |entry|
    if entry.directory? and entry.path == "/" + @user.folder then folder = entry end
  end
  if not folder then
    begin
      db_session.create_folder(@user.folder)
    rescue Dropbox::UnsuccessfulResponseError # extra safety
      flash[:info] = 'Please specify a folder for your wiki.'
      redirect '/settings'
    end
  end
  pages = db_session.list(@user.folder)
  @pages = []
  pages.each do |entry|
    if entry.path == "/#{@user.folder}/#{page}" then reqpage = entry end
    @pages.push(entry.path.gsub("/#{@user.folder}/", ""))
  end
  @cur_page = {:name => page}
  if reqpage then
    @cur_page[:text] = db_session.download("/#{@user.folder}/#{page}")
  end
  haml :pages
end

post '/pages/:page' do |page|
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  user = User[:email => db_session.account.email]
  if not user.folder then
    flash[:info] = 'Please specify a folder for your wiki.'
    redirect '/settings'
  end
  db_session.mode=(:dropbox)
  root = db_session.list("/")
  root.each do |entry|
    if entry.directory? and entry.path == "/" + user.folder then folder = entry end
  end
  if not folder then db_session.create_folder(user.folder) end
  db_session.upload(StringIO.new(params[:text]), "/#{user.folder}", {:as => page})
  flash[:info] = "Saved #{page}."
  redirect "/pages/#{page}"
end

get '/pages/:page/delete' do |page|
  return redirect '/auth' unless session[:db_session]
  db_session = Dropbox::Session.deserialize(session[:db_session])
  return redirect '/auth' unless db_session.authorized?
  user = User[:email => db_session.account.email]
  if not user.folder then
    flash[:info] = 'Please specify a folder for your wiki.'
    redirect '/settings'
  end
  db_session.mode=(:dropbox)
  root = db_session.list("/")
  root.each do |entry|
    if entry.directory? and entry.path == "/" + user.folder then folder = entry end
  end
  if not folder then db_session.create_folder(user.folder) end
  db_session.delete("/#{user.folder}/#{page}")
  flash[:info] = "Deleted #{page}."
  redirect "/pages"
end

get '/screen.css' do
  content_type 'text/css'
  sass :screen
end

helpers do
  def csrf_token
    Rack::Csrf.csrf_token(env)
  end

  def csrf_tag
    Rack::Csrf.csrf_tag(env)
  end
end

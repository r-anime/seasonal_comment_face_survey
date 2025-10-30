require 'dotenv/load'
require 'sassc'
require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/reloader' if development?
require 'gon-sinatra'

also_reload './src/**/*.rb' if development?
also_reload './app.rb' if development?

require './src/models/survey'
require './src/services/chart_service'
require './src/services/github_service'

CACHE_DIR = "/tmp/seasonal_comment_face_survey_cache"

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
    also_reload './src/**/*.rb'
    also_reload './app.rb'
  end
  register Gon::Sinatra

  set :strict_paths, false

  before do
    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  after do
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    duration = end_time - @start_time
    puts "#{Time.now} [#{request.request_method}] #{request.path} took #{(duration * 1000).round(2)} ms"
  end

  on_start do
    puts "===== Booting up ====="
    @@chart_service = ChartService.new(CACHE_DIR)
    @@github_service = GithubService.new(CACHE_DIR, ENV["GITHUB_TOKEN"])
  end

  helpers do
    def protected!
      return if authorized?
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials[-1] == ENV['MOD_PASSWORD']
    end
  end

  get '/stylesheets/:name.css' do
    scss :"stylesheets/#{params[:name]}"
  end

  get '/' do
    redirect '/surveys'
  end

  get '/surveys' do
    @surveys = Survey.all
    erb :'surveys/index', locals: {template: [:survey, :index]}
  end

  get '/surveys/new' do
    protected!
    erb :'surveys/new', locals: {template: [:survey, :new]}
  end

  post '/surveys' do
    protected!
    sheet_id = params[:sheet_id]
    gid = params[:gid]
    sheet_url = params[:sheet_url]

    if sheet_url && !sheet_url.strip.empty?
      # Parse the sheet_url for sheet_id and gid
      # Example URL: https://docs.google.com/spreadsheets/d/SheetID/edit#gid=GID
      match = sheet_url.match(%r{/d/([^/]+)/.*gid=(\d+)})
      if match
        sheet_id = match[1]
        gid = match[2]
      else
        raise "Invalid Google Sheet URL format"
      end
    end

    survey = Survey.new(
      year: params[:year],
      season: params[:season],
      name: params[:name],
      sheet_id: sheet_id,
      gid: gid,
      misc: {} # TODO
    )

    if survey.save
      redirect "/surveys/#{survey.year}/#{survey.season}"
    else
      @errors = survey.errors.full_messages
      erb :'surveys/new'
    end
  end

  get '/surveys/:year/:season' do
    year = params[:year].to_i
    season = params[:season]
    gon.defaultTab = "#ratings"
    gon.baseballsTopWeighted = {multiplier: ChartService::BASEBALLS_TOP_WEIGHTED_MULTIPLIER, weights: ChartService::BASEBALLS_TOP_WEIGHTED_WEIGHTS}
    gon.chartData = @@chart_service.generate_data(year, season)
    gon.commentFaceLinks = @@github_service.fetch_comment_faces(year, season)
    gon.prevCommentFaceLinks = @@github_service.fetch_prev_comment_faces(year, season)
    gon.seasons = {
      current: {year: year, season: season.capitalize},
      prev: {year: @@github_service.get_prev_season(year, season)[0], season: @@github_service.get_prev_season(year, season)[1].capitalize}
    }
    erb :'surveys/show', locals: {template: [:survey, :show]}
  end

end

App.run! if __FILE__ == $0

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
    puts "[#{request.request_method}] #{request.path} took #{(duration * 1000).round(2)} ms"
  end

  on_start do
    puts "===== Booting up ====="
    @@chart_service = ChartService.new
    @@github_service = GithubService.new(ENV["GITHUB_TOKEN"])
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
    erb :'surveys/new', locals: {template: [:survey, :new]}
  end

  post '/surveys' do
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
      gid: gid
    )

    if survey.save
      redirect "/surveys/#{survey.year}/#{survey.season}"
    else
      @errors = survey.errors.full_messages
      erb :'surveys/new'
    end
  end

  get '/surveys/:year/:season' do
    year = params[:year]
    season = params[:season]
    gon.baseballsTopWeighted = {multiplier: ChartService::BASEBALLS_TOP_WEIGHTED_MULTIPLIER, weights: ChartService::BASEBALLS_TOP_WEIGHTED_WEIGHTS}
    gon.chartData = @@chart_service.generate_data(year, season)
    gon.commentFaceLinks = @@github_service.fetch_comment_faces(year, season)
    erb :'surveys/show', locals: {template: [:survey, :show]}
  end

end

App.run! if __FILE__ == $0

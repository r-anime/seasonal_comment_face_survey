require 'active_support'
require 'active_support/cache'
require 'csv'
require 'httparty'

require './src/models/survey'

class ChartService
  CACHE_EXPIRY_TIME = 60 * 15 # 15 minutes

  RESPONDENT_ID_FIELD = "Respondent ID"

  RATING_QUESTION = "How much do you like ".downcase
  RATINGS_SCORES = 1..5

  BASEBALLS_TOP_WEIGHTED_MULTIPLIER = 100.0
  BASEBALLS_TOP_WEIGHTED_WEIGHTS = {1 => -1, 2 => -0.5, 3 => 0, 4 => 1, 5 => 3}

  LAST_SEASONS_COMPARISON_QUESTION = "last season's".downcase
  LAST_SEASONS_COMPARISONS_SCORES = 1..5

  HOF_QUESTION = /^#seasonal/
  HOF_SCORES = 0..3

  MISC_QUESTIONS = [{question_regex: /Google Forms/i, type: :linear, min: 0, max: 10}] # TODO make part of DB

  def initialize(cache_dir)
    @cache = ActiveSupport::Cache::FileStore.new(File.join(cache_dir, "chart_service"), expires_in: CACHE_EXPIRY_TIME)
  end

  def generate_data(year, season)
    survey = Survey.find_by(year: year, season: season)

    csv_str = fetch_csv_str(survey)

    csv = CSV.parse(csv_str, headers: true)

    dedupped_data = csv.group_by { |row| row[RESPONDENT_ID_FIELD] }.values.map(&:last)

    ratings = calculate_ratings_data(csv.headers, dedupped_data)
    last_seasons_comparisons = calculate_last_seasons_comparisons_data(csv.headers, dedupped_data)
    hof = calculate_hof_data(csv.headers, dedupped_data)
    misc = calculate_misc_data(csv.headers, dedupped_data)

    {debug: dedupped_data[0].to_a.to_h, ratings: ratings, lastSeasonComparisons: last_seasons_comparisons, hof: hof, misc: misc}
  end

  def fetch_csv_str(survey)
    url = "https://docs.google.com/spreadsheets/d/#{survey.sheet_id}/export?format=csv&gid=#{survey.gid}"
    @cache.fetch([:csv, url]) do
      start = Time.now
      $logger.info "cache miss: ChartService#fetch_csv_str: #{url}"
      csv_resp = HTTParty.get(url)
      raise "error fetching csv from google sheet: id: #{survey.sheet_id}, gid: #{survey.gid}: #{csv_resp.parsed_response}" unless csv_resp.success?

      csv_str = csv_resp.body
      $logger.info "csv fetch took: #{Time.now - start}"
      csv_str
    end
  end

  def calculate_ratings_data(csv_headers, dedupped_data)
    face_scores = Hash.new { |h, k| h[k] = RATINGS_SCORES.map { |score| [score, 0] }.to_h }
    indexes = csv_headers.each_with_index
                         .select { |(question, _index)| question.downcase.include?(RATING_QUESTION) }
                         .map { |question, index| [question[/#(.+\b)/, 1], index] }
                         .to_h

    dedupped_data.each do |row|
      indexes.each do |face_code, index|
        face_scores[face_code][0]
        score_str = row[index]
        next unless score_str
        score = score_str.to_i
        face_scores[face_code][score] += 1
      end
    end

    face_scores = face_scores.map do |face_code, hash|
      stats = calculate_stats(hash, true)
      stats.delete(:score)
      [face_code, stats]
    end.to_h

    indexes.each do |face_code, index|
      face_scores[face_code]["question"] = csv_headers[index]
    end

    face_scores
  end

  def calculate_last_seasons_comparisons_data(csv_headers, dedupped_data)
    face_scores = Hash.new { |h, k| h[k] = LAST_SEASONS_COMPARISONS_SCORES.map { |score| [score, 0] }.to_h }
    indexes = csv_headers.each_with_index
                         .select { |(question, _index)| question.downcase.include?(LAST_SEASONS_COMPARISON_QUESTION) }
                         .map { |question, index| [question[/#(\w+\b)/, 1], index] }
                         .to_h

    dedupped_data.each do |row|
      indexes.each do |face_code, index|
        face_scores[face_code][0]
        score_str = row[index]
        next unless score_str
        score = score_str.to_i
        face_scores[face_code][score] += 1
      end
    end

    face_scores = face_scores.map do |face_code, hash|
      stats = calculate_stats(hash, false)
      stats.delete(:score)
      [face_code, stats]
    end.to_h

    indexes.each do |face_code, index|
      face_scores[face_code]["question"] = csv_headers[index]
    end

    face_scores
  end

  def calculate_hof_data(csv_headers, dedupped_data)
    face_scores = Hash.new { |h, k| h[k] = HOF_SCORES.map { |score| [score, 0] }.to_h }
    indexes = csv_headers.each_with_index
                         .select { |(question, _index)| question.downcase.match?(HOF_QUESTION) }
                         .map { |question, index| [question[/#(.+\b)/, 1], index] }
                         .to_h

    dedupped_data.each do |row|
      indexes.each do |face_code, index|
        score_str = row[index]
        next unless score_str
        score = score_str.to_i
        face_scores[face_code][score] += 1
      end
    end

    face_scores = face_scores.map do |face_code, hash|
      stats = calculate_stats(hash)
      stats[:ratings].delete(0)
      stats.delete(:avg)
      [face_code, stats]
    end.to_h

    indexes.each do |face_code, index|
      face_scores[face_code]["question"] = csv_headers[index]
    end

    face_scores
  end

  def calculate_misc_data(csv_headers, dedupped_data)
    MISC_QUESTIONS.map do |misc|
      question, index = csv_headers.each_with_index
                                   .select { |(question, _index)| question.downcase.match?(misc[:question_regex]) }
                                   .map { |question, index| [question, index] }
                                   .first(1)[0]
      {question: question, type: misc[:type], data: calc_misc_linear(dedupped_data, index, misc[:min]..misc[:max])}
    end
  end

  def calc_misc_linear(dedupped_data, index, range)
    scores = range.map { |score| [score, 0] }.to_h

    dedupped_data.each do |row|
      score_str = row[index]
      next unless score_str
      score = score_str.to_i
      scores[score] += 1
    end

    stats = calculate_stats(scores, false)
    stats.delete(:score)

    stats
  end

  def calculate_stats(ratings, include_baseballs_top_weighted = false)
    total = 0
    avg = 0
    baseballs_top_weighted = 0
    ratings.each do |(score, count)|
      total += count
      avg += score * count
      baseballs_top_weighted += BASEBALLS_TOP_WEIGHTED_WEIGHTS[score] * count if include_baseballs_top_weighted
    end
    score = avg
    avg /= total.to_f
    stats = {responses: total, score: score, avg: avg}
    if include_baseballs_top_weighted
      baseballs_top_weighted *= BASEBALLS_TOP_WEIGHTED_MULTIPLIER
      baseballs_top_weighted /= total
      stats[:baseballsTopWeighted] = baseballs_top_weighted
    end
    stats[:ratings] = ratings
    stats
  end
end



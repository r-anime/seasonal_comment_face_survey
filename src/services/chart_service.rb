require 'csv'
require 'httparty'

require './src/models/survey'

class ChartService
  RESPONDENT_ID_FIELD = "Respondent ID"

  RATING_QUESTION = "How much do you like ".downcase
  RATINGS_SCORES = 1..5

  BASEBALLS_TOP_WEIGHTED_MULTIPLIER = 100.0
  BASEBALLS_TOP_WEIGHTED_WEIGHTS = {1 => -1, 2 => -0.5, 3 => 0, 4 => 1, 5 => 3}

  LAST_SEASONS_COMPARISON_QUESTION = "last season's".downcase
  LAST_SEASONS_COMPARISONS_SCORES = 1..5

  HOF_QUESTION = /^#seasonal/
  HOF_SCORES = 0..3

  def generate_data(year, season)
    survey = Survey.find_by(year: year, season: season)
    csv_resp = HTTParty.get(csv_download_url(survey.sheet_id, survey.gid))
    raise "error fetching csv from google sheet: id: #{survey.sheet_id}, gid: #{survey.gid}: #{csv_resp.parsed_response}" unless csv_resp.success?
    csv = CSV.parse(csv_resp.body, headers: true)

    dedupped_data = csv.group_by { |row| row[RESPONDENT_ID_FIELD] }.values.map(&:last)

    ratings = calculate_ratings_data(csv.headers, dedupped_data)
    last_seasons_comparisons = calculate_last_seasons_comparisons_data(csv.headers, dedupped_data)
    hof = calculate_hof_data(csv.headers, dedupped_data)

    {debug: dedupped_data[0].to_a.to_h, ratings: ratings, last_season_comparisons: last_seasons_comparisons, hof: hof}
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

    face_scores
  end

  def calculate_last_seasons_comparisons_data(csv_headers, dedupped_data)
    []
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

    face_scores
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

  def csv_download_url(sheet_id, gid)
    "https://docs.google.com/spreadsheets/d/#{sheet_id}/export?format=csv&gid=#{gid}"
  end
end



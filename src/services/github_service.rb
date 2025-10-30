require 'active_support'
require 'active_support/cache'
require 'httparty'

class GithubService
  COMMENT_FACE_GITHUB = "https://api.github.com/repos/r-anime/comment-face-assets/contents/source_seasonal_faces/"
  COMMENT_FACE_TREE_GITHUB = "https://api.github.com/repos/r-anime/comment-face-assets/git/trees/"
  COMMENT_FACE_GITHUB_DL_LINK = "https://raw.githubusercontent.com/r-anime/comment-face-assets/master/source_seasonal_faces/"

  CACHE_EXPIRY_TIME = 60 * 60 * 24 #

  PREV_SEASON = {
    "winter" => [-1, "fall"],
    "fall" => [0, "summer"],
    "summer" => [0, "spring"],
    "spring" => [0, "winter"],
  }

  NEXT_SEASON = {
    "winter" => [0, "spring"],
    "spring" => [0, "summer"],
    "summer" => [0, "fall"],
    "fall" => [1, "winter"],
  }

  def initialize(cache_dir, token = nil)
    @cache = ActiveSupport::Cache::FileStore.new(File.join(cache_dir, "github_service"), expires_in: CACHE_EXPIRY_TIME)
    @token = token
    @headers = {}
    @headers["Authorization"] = "Bearer #{@token}" if @token
  end

  def get_next_season(year, season)
    [year + NEXT_SEASON[season][0], NEXT_SEASON[season][1]]
  end

  def get_prev_season(year, season)
    [year + PREV_SEASON[season][0], PREV_SEASON[season][1]]
  end

  def fetch_prev_comment_faces(year, season)
    fetch_comment_faces(*get_prev_season(year, season))
  end

  def fetch_comment_faces(year, season)
    tree_sha = fetch_tree_sha(year, season)

    tree_json = fetch_tree_json(tree_sha)

    links = tree_json["tree"].select do |git|
      git["type"] == "blob"
    end.reject do |git|
      git["path"].include?('original')
    end.map do |git|
      [git["path"].split("/")[0], COMMENT_FACE_GITHUB_DL_LINK + "#{year}%20#{season}/source/#{git["path"]}"]
    end.to_h

    links
  end

  def fetch_tree_sha(year, season)
    url = COMMENT_FACE_GITHUB + "#{year}%20#{season}"
    @cache.fetch([:tree_sha, url]) do
      start = Time.now
      $logger.info "cache miss: GithubService#fetch_tree_sha: #{url}"
      tree_sha_resp = HTTParty.get(url, headers: @headers)
      raise "error fetching comment faces tree sha from r/anime comment-face-assets github repo: #{tree_sha_resp}" unless tree_sha_resp.success?

      tree_sha = tree_sha_resp.parsed_response.find { |git| git["name"] == "source" }&.[]("sha")
      $logger.info "tree sha took: #{Time.now - start}"
      tree_sha
    end
  end

  def fetch_tree_json(tree_sha)
    url = COMMENT_FACE_TREE_GITHUB + tree_sha + "?recursive=true"
    @cache.fetch([:tree_json, url]) do
      start = Time.now
      $logger.info "cache miss: GithubService#fetch_tree_json: #{url}"
      tree_resp = HTTParty.get(url, headers: @headers)
      raise "error fetching comment faces tree from r/anime comment-face-assets github repo: #{tree_resp}" unless tree_resp.success?

      json = tree_resp.parsed_response
      $logger.info "tree json took: #{Time.now - start}"
      json
    end
  end
end

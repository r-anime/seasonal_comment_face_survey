require 'httparty'

class GithubService
  COMMENT_FACE_GITHUB = "https://api.github.com/repos/r-anime/comment-face-assets/contents/source_seasonal_faces/"
  COMMENT_FACE_TREE_GITHUB = "https://api.github.com/repos/r-anime/comment-face-assets/git/trees/"
  COMMENT_FACE_GITHUB_DL_LINK = "https://raw.githubusercontent.com/r-anime/comment-face-assets/master/source_seasonal_faces/"

  def initialize(token = nil)
    @token = token
  end

  def fetch_comment_faces(year, season)
    headers = {"Authorization" => "Bearer #{@token}"} if @token

    puts "url: #{COMMENT_FACE_GITHUB + "#{year}%20#{season}"}"
    tree_sha_resp = HTTParty.get(COMMENT_FACE_GITHUB + "#{year}%20#{season}", headers: headers)
    raise "error fetching comment faces tree sha from r/anime comment-face-assets github repo: #{tree_sha_resp}" unless tree_sha_resp.success?
    tree_sha = tree_sha_resp.parsed_response.find { |git| git["name"] == "source" }&.[]("sha")

    tree_resp = HTTParty.get(COMMENT_FACE_TREE_GITHUB + tree_sha + "?recursive=true", headers: headers)
    raise "error fetching comment faces tree from r/anime comment-face-assets github repo: #{tree_resp}" unless tree_resp.success?

    tree_resp.parsed_response["tree"].select do |git|
      git["type"] == "blob"
      # end.select do |git|
      #   git["path"].count("/") <= 1
    end.reject do |git|
      git["path"].include?('original')
      # end.select do |git|
      #   git["path"].include?('original')
      # end.map do |git|
      #   [git["path"].split("/")[0], COMMENT_FACE_GITHUB_DL_LINK + "#{year}%20#{season}/#{git["path"]}"]
    end.map do |git|
      [git["path"].split("/")[0], COMMENT_FACE_GITHUB_DL_LINK + "#{year}%20#{season}/source/#{git["path"]}"]
    end.to_h
  end
end

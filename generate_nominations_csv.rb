require 'csv'
require 'httparty'
require 'json'

ANIME_LOOKUP_CACHE = 'anime_lookup.cache.json'
REDDIT_COMMENT_JSON_PATH = 'reddit.json'
# REDDIT_COMMENT_JSON_PATH = 'reddit_2025_summer.json'
OUTPUT_CSV_PATH = 'comment_faces.csv'
LOOKUP_URL = 'https://api.trace.moe/search?anilistInfo&cutBorders&url='
SIMILARITY_THRESHOLD = 0.90

FACES = ["disapproval", "approval", "blush", "confused", "cool", "depression", "disdain", "foodie", "hype", "laugh", "listen", "love", "neat", "pout", "secret", "shock", "think", "tired", "pls", "smug"]
FACE_REGEX = /(seasonal\s*)?(#{FACES.join("|")})\b/i
LINK_REGEX = /\[(.*?)\]\((http.*?)\)/i

class Submission
  attr_accessor :face, :anime_name, :link, :submitter, :line, :comment_link

  def initialize(face, anime_name, link, submitter, line, comment_link)
    @face = face
    @anime_name = anime_name
    @link = link
    @submitter = submitter
    @line = line
    @comment_link = comment_link
  end

  def face
    @face || "UNKNOWN"
  end

  def anime_name
    @anime_name || "UNKNOWN"
  end
end

# TODO perhaps implement dedeupping via overlapping time ranges (probably for manual review)
# TODO sort by face and then anime? and then time created (earlier better)? might need 2 sorts to use comment info
# DONE handle multiple comment faces listed at once.
def main
  post = fetch_reddit_post
  post_link = "https://www.reddit.com/#{post[0]["data"]["children"][0]["data"]["subreddit_name_prefixed"]}/comments/#{post[0]["data"]["children"][0]["data"]["id"]}"
  puts "post_link: #{post_link}"

  comments = []
  collect_comments(comments, post[1]["data"]["children"])
  # comments = [{"body" =>"[#SeasonalCool](https://i.imgur.com/MKXK75R.mp4): Could be interesting as an animated one (though it needs a bit of fine trimming to get a good loop). [Still 1](https://i.imgur.com/Mw05zmM.png), [Still 2](https://i.imgur.com/saDSyWQ.png), [Still 3](https://i.imgur.com/0HAK6wF.png), [Still 4](https://i.imgur.com/91zKPHA.png), [Still 5](https://i.imgur.com/DdNnrFP.png) (this last one I think has the most potential as a still imo)"}]
  puts "top level: #{post[1]["data"]["children"].size}, comments: #{comments.size}"

  # total_links = comments.map { |c| c["body"].scan(/\]\(http/).size }.sum
  total_links = comments.map { |c| c["body"].split("\n\n").reject { |line| line.start_with?(/\s*&gt;/) }.map { |line| line.scan(/\]\(http/).size }.sum }.sum
  puts "total_links: #{total_links}"

  File.write(ANIME_LOOKUP_CACHE, "{}") unless File.exist?(ANIME_LOOKUP_CACHE)
  $anime_lookup_cache = JSON.parse(File.read(ANIME_LOOKUP_CACHE))

  links = Set.new
  submissions = []

  # csv_str = CSV.generate do |csv|
  #   csv << ['Anime Name', 'Face', 'Image Link', 'Image', 'Submitter', 'Notes', 'Comment Link']

  index = 1
  comments
  # .first(1) # DEBUG
  # .drop(13)
  # .first(1)
    .each_with_index do |comment, i|
    parse_comment(comment) do |face, link, comment_id, author, line|
      next if link.include?("reddit.com")
      index += 1
      comment_link = "#{post_link}/comment/#{comment_id}"
      puts "i: #{i}, face: #{face}, link: #{link}, comment_link: #{comment_link}"
      links << link
      # submissions << [fetch_anime(link), face, link, "=IMAGE(C#{index})", "u/#{author}", line, comment_link]
      submissions << Submission.new(face, fetch_anime(link), link, "u/#{author}", line, comment_link)
      # submissions << [fetch_anime(link), face, link, "=IMAGE(C#{index + i})", "u/#{author}", line, comment_link] # DEBUG
      # break # DEBUG
    end
  end
  # break if comment["body"].include?("This one would make for a great #seasonaldisdain")
  # submissions << [] # DEBUG
  #   end
  # end

  submissions.sort_by! { |s| [s.face, s.anime_name, s.submitter] } # DE DEBUG

  # used_anime_names = ['You and Idol Precure', 'The Gorilla God', 'Apocalypse Hotel', 'Lycoris Recoil']
  # used_comment_faces = ['Shock', 'Laugh', 'Disapproval', 'Neat']
  used_anime_names = []
  used_comment_faces = []

  submissions.reject! { |s| used_anime_names.any? { |n| s.anime_name.include?(n) } }
  submissions.reject! { |s| used_comment_faces.include?(s.face) }

  csv_str = CSV.generate do |csv|
    csv << ['Anime Name', 'Face', 'Image Link', 'Image', 'Score', 'Submitter', 'Notes', 'Comment Link']

    index = 1
    unknowns, knowns = submissions.partition { |submission| submission.anime_name == "UNKNOWN" } # DE DEBUG
    # unknowns, knowns = [[], submissions] # DE DEBUG
    (knowns + unknowns).each do |submission|
      index += 1
      csv << [submission.anime_name, submission.face, submission.link, "=IMAGE(C#{index})", '', submission.submitter, submission.line, submission.comment_link]
    end
  end

  puts "comments: #{comments.size}"
  puts "total_links: #{total_links}"
  missing_links = comments.flat_map { |c| c["body"].scan(/\[(.*?)\]\((http.*?)\)/).map { |match| ["#{post_link}/comment/#{c["id"]}", match] } }.reject { |arr| links.include?(arr[1][1]) }
  puts "missing_links: #{missing_links}"
  File.write(OUTPUT_CSV_PATH, csv_str)
end

def fetch_reddit_post
  JSON.parse(File.read(REDDIT_COMMENT_JSON_PATH))
end

def save_anime_lookup_cache
  path = ANIME_LOOKUP_CACHE
  tmp_path = path.split(".").insert(1, "tmp").join(".")
  File.write(tmp_path, JSON.pretty_generate($anime_lookup_cache))
  File.rename(tmp_path, path)
end

def collect_comments(comments_array, comments)
  comments.map { |c| c["data"] }.each do |comment|
    # comments_array << comment if comment["id"] == "n5o7hsh" # DE DEBUG
    comments_array << comment if !comment["distinguished"] && comment["body"] # DE DEBUG
    if comment["replies"] && !comment["replies"].empty? # DE DEBUG
      collect_comments(comments_array, comment["replies"]["data"]["children"]) # DE DEBUG
    end # DE DEBUG
  end
end

# TODO perhaps implement retrying
def fetch_anime(image_link)
  if $anime_lookup_cache[image_link]
    puts "returning cached lookup for #{image_link}"
    return fetch_anime_name($anime_lookup_cache[image_link])
  end

  # return "TODO anime name" if true # DEBUG

  url = LOOKUP_URL + image_link
  puts "fetching #{url}"
  resp = HTTParty.get(url)
  if !resp.ok? || (resp.parsed_response["error"] && !resp.parsed_response["error"].empty? && resp.parsed_response["error"] != "200")
    $stderr.puts "Error fetching response: #{resp}"
    return "UNKNOWN (#{resp.code})"
  end
  data = resp.parsed_response

  data["result"].select! { |result| result["similarity"] >= SIMILARITY_THRESHOLD }
  $anime_lookup_cache[image_link] = data
  save_anime_lookup_cache
  fetch_anime_name(data)
end

def fetch_anime_name(data)
  return "UNKNOWN" if data["result"].empty?
  matching_titles = data["result"].map { |r| [get_name(r["anilist"]), r["similarity"]] }
  if matching_titles.map { |arr| arr[0] }.to_set.size > 1
    puts "multiple shows passes similarity threshold: #{matching_titles}"
  end
  get_name(data["result"][0]["anilist"])
end

def get_name(data)
  data["title"]["english"] || data["title"]["romaji"] || data["title"]["native"]
end

def parse_comment(comment_data)
  # body = comment_data["body"].strip.gsub(/(\S)\n\s*(\*|\-)/, "\\1\n\n\\2") # to put lists on different lines
  body = comment_data["body"]
  comment_id = comment_data["id"]
  author = comment_data["author"]
  puts "body: #{body}"
  puts "\n***************\n\n"

  current_face = nil

  lines = body.split("\n\n")
  lines.each do |big_line|
    big_line.strip!
    # body.scan(Regexp.union(FACE_REGEX, LINK_REGEX)) do |match|
    next if big_line.start_with?(/\s*&gt;/)
    big_line.split("\n").each do |line|
      line.scan(Regexp.union(FACE_REGEX, LINK_REGEX)) do |match|
        puts "\ncurrent_face: #{current_face}, match: #{match.inspect}"
        if match[1]
          current_face = match[1].capitalize
        elsif match[3]
          if match[2][FACE_REGEX]
            puts "match2: #{match[2]}"
            puts "scan: #{match[2].scan(FACE_REGEX)}"
            match[2].scan(FACE_REGEX).each do |inner_match|
              current_face = inner_match[1].capitalize
              yield current_face, match[3], comment_id, author, line
            end
          else
            yield current_face, match[3], comment_id, author, line
          end
        else
          puts "match: #{match.inspect}"
          raise "could not process comment"
        end
      end
    end
  end

  # yield "TODO face", "TODO link", comment_data["id"]
end

main

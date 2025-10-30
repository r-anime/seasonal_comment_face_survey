require 'dotenv/load'
require 'logger'
$logger = Logger.new($stdout)

require 'httparty'
require 'securerandom'
require_relative './src/services/github_service'

POINTS_TO_ALLOCATE = 6
POINTS_ALLOTTED_MAX = 3
# PAGE_WIDTH = 1150
PAGE_WIDTH = 700
AFTER_PUBLISH = false
# AFTER_PUBLISH = true
RATING_MIN = 1
RATING_MAX = 5

HOF_COMMENT_FACES_PER_ROW = 3

GITHUB_TOKEN = ENV["GITHUB_TOKEN"]
API_KEY = ENV["TALLY_API_KEY"]
BASE_URL = "https://api.tally.so"

GET_WORKSPACES = "/workspaces"
FORMS = "/forms"
CACHE_DIR = "/tmp/seasonal_comment_face_survey_cache"

def main(year, season)
  raise "invalid season: #{season}" unless GithubService::PREV_SEASON.include?(season)

  @github_service = GithubService.new(CACHE_DIR, GITHUB_TOKEN)

  comment_faces = @github_service.fetch_comment_faces(year, season)
  $logger.info "comment_faces: #{comment_faces}"

  existing_form_id = fetch_existing_form(year, season)
  # existing_form_id = nil
  if existing_form_id.nil?
    $logger.info "creating new survey"
    existing_form_id = create_new_survey(year, season)
  end
  $logger.info "existing_form_id: #{existing_form_id}"

  mention_ids = {
    points: {
      name: "points",
      mention_uuid: SecureRandom.uuid,
      field_uuid: SecureRandom.uuid,
      block_group_uuid: SecureRandom.uuid
    },
    respondent_id: {
      uuid: SecureRandom.uuid
    }
  }
  blocks = calculate_survey_blocks(comment_faces, mention_ids, year, season)
  update_form(existing_form_id, get_survey_title(year, season), mention_ids, blocks)
  # $logger.info "fetch_workspace: #{fetch_workspace}"
end

def fetch_existing_form(year, season)
  forms = HTTParty.get(BASE_URL + FORMS, headers: {"Authorization" => "Bearer #{API_KEY}"}).parsed_response["items"]

  forms.select { |form| form["name"] }
       .find { |form| form["name"].downcase.include?("face survey") && form["name"].downcase.include?("for #{season} #{year}") }
    &.[]("id")
end

def create_new_survey(year, season)
  post_new_survey(get_survey_title(year, season))
end

def post_new_survey(title)
  body = {
    status: "DRAFT",
    blocks: [
      {
        uuid: SecureRandom.uuid,
        type: "FORM_TITLE",
        groupUuid: SecureRandom.uuid,
        groupType: "FORM_TITLE",
        payload: {
          html: title
        }
      }
    ],
    settings: {
      saveForLater: true,
      hasProgressBar: true,
      # styles: {
      #   advanced: {
      #     pageWidth: PAGE_WIDTH
      #   }
      # }
    }
  }
  resp = HTTParty.post(BASE_URL + FORMS, body: body.to_json,
                       headers: {"Authorization" => "Bearer #{API_KEY}", "Content-Type" => "application/json"})
  raise "Error creating survey: #{resp.parsed_response}" unless resp.success?
  resp.parsed_response["id"]
end

def update_form(form_id, title, mention_ids, blocks)
  body = {
    status: AFTER_PUBLISH ? "PUBLISHED" : "DRAFT",
    blocks: [
      {
        uuid: SecureRandom.uuid,
        type: "FORM_TITLE",
        groupUuid: SecureRandom.uuid,
        groupType: "FORM_TITLE",
        payload: {
          html: title,
          mentions: [
            {
              "uuid": mention_ids[:points][:mention_uuid],
              "field": {
                "uuid": mention_ids[:points][:field_uuid],
                "type": "CALCULATED_FIELD",
                "questionType": "CALCULATED_FIELDS",
                "blockGroupUuid": mention_ids[:points][:block_group_uuid],
                "title": "points",
                "calculatedFieldType": "NUMBER"
              }
            },
            {
              "uuid": mention_ids[:respondent_id][:uuid],
              "field": {
                "uuid": "respondentId",
                "type": "METADATA",
                "questionType": "FORM_TITLE",
                "blockGroupUuid": "respondentId",
                "title": "respondentId"
              }
            },
          ]
        }
      }
    ] + blocks,
    settings: {
      saveForLater: true,
      hasProgressBar: true,
      # styles: {
      #   advanced: {
      #     pageWidth: PAGE_WIDTH
      #   }
      # }
    }
  }
  # $logger.info "body: #{body}"
  File.write("body.json", body.to_json)
  resp = HTTParty.patch(BASE_URL + FORMS + "/" + form_id, body: body.to_json,
                        headers: {"Authorization" => "Bearer #{API_KEY}", "Content-Type" => "application/json"})
  raise "Error creating survey: #{resp.parsed_response}" unless resp.success?
  mention_ids
end

def calculate_survey_blocks(comment_faces, mention_ids, year, season)
  prev_comment_faces = @github_service.fetch_prev_comment_faces(year, season)
  calculate_rating_blocks(comment_faces) +
    [{
       "uuid": SecureRandom.uuid,
       "type": "PAGE_BREAK",
       "groupUuid": SecureRandom.uuid,
       "groupType": "PAGE_BREAK",
       "payload": {
         "index": 0,
         "isQualifiedForThankYouPage": false,
         "isThankYouPage": false,
         "isFirst": true,
         "isLast": false
       }
     },
    ] +
    calculate_rating_comparison_blocks(comment_faces, prev_comment_faces) +
    [{
       "uuid": SecureRandom.uuid,
       "type": "PAGE_BREAK",
       "groupUuid": SecureRandom.uuid,
       "groupType": "PAGE_BREAK",
       "payload": {
         "index": 1,
         "isQualifiedForThankYouPage": false,
         "isThankYouPage": false,
         "isFirst": false,
         "isLast": false
       }
     },
    ] +
    calculate_hof_blocks(comment_faces, mention_ids) +
    [{
       "uuid": SecureRandom.uuid,
       "type": "PAGE_BREAK",
       "groupUuid": SecureRandom.uuid,
       "groupType": "PAGE_BREAK",
       "payload": {
         "index": 2,
         "isQualifiedForThankYouPage": false,
         "isThankYouPage": false,
         "isFirst": false,
         "isLast": false
       }
     },
    ] +
    calculate_other_questions_blocks +
    [{
       "uuid": SecureRandom.uuid,
       "type": "PAGE_BREAK",
       "groupUuid": SecureRandom.uuid,
       "groupType": "PAGE_BREAK",
       "payload": {
         "index": 3,
         "isQualifiedForThankYouPage": true,
         "isThankYouPage": true,
         "isFirst": false,
         "isLast": true
       }
     },
    ] +
    calculate_thank_you_page_blocks(get_survey_title(year, season), mention_ids)
end

def calculate_rating_blocks(comment_faces)
  comment_faces.flat_map do |comment_face, download_link|
    group_uuid = SecureRandom.uuid
    row_uuid = SecureRandom.uuid
    col_uuid = SecureRandom.uuid
    blocks =
      [
        {
          "uuid": SecureRandom.uuid,
          "type": "IMAGE",
          "groupUuid": group_uuid,
          "groupType": "IMAGE",
          "payload": {
            "images": [
              {
                "name": download_link,
                "url": download_link
              }
            ],
            "columnListUuid": row_uuid,
            "columnUuid": SecureRandom.uuid,
            "columnRatio": 25,
            "hasCaption": true,
            "caption": "Current ##{comment_face}"
          }
        },
        {
          "uuid": SecureRandom.uuid,
          "type": "TITLE",
          "groupUuid": group_uuid,
          "groupType": "QUESTION",
          "payload": {
            "columnListUuid": row_uuid,
            "columnUuid": col_uuid,
            "columnRatio": 75,
            "safeHTMLSchema": [
              [
                "How much do you like ##{comment_face}?"
              ]
            ]
          }
        },
        {
          "uuid": SecureRandom.uuid,
          "type": "LINEAR_SCALE",
          "groupUuid": group_uuid,
          "groupType": "LINEAR_SCALE",
          "payload": {
            "isRequired": false,
            "start": RATING_MIN,
            "end": RATING_MAX,
            "step": 1,
            "columnListUuid": row_uuid,
            "columnUuid": col_uuid,
            "columnRatio": 75,
            "hasCenterLabel": true,
            "centerLabel": "Mid",
            "hasLeftLabel": true,
            "leftLabel": "Bad",
            "hasRightLabel": true,
            "rightLabel": "Good"
          }
        }
      ]
    blocks << {
      "uuid": SecureRandom.uuid,
      "type": "DIVIDER",
      "groupUuid": SecureRandom.uuid,
      "groupType": "DIVIDER",
      "payload": {}
    }

    blocks
  end
end

def calculate_rating_comparison_blocks(comment_faces, prev_comment_faces)
  comment_faces.flat_map do |comment_face, download_link|
    next [] unless (prev_comment_faces[comment_face])

    group_uuids = [SecureRandom.uuid, SecureRandom.uuid]
    row_uuids = [SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid]
    col_uuids = [SecureRandom.uuid, SecureRandom.uuid]
    blocks =
      [
        {
          "uuid": SecureRandom.uuid,
          "type": "IMAGE",
          "groupUuid": group_uuids[1],
          "groupType": "IMAGE",
          "payload": {
            "images": [
              {
                "name": prev_comment_faces[comment_face],
                "url": prev_comment_faces[comment_face]
              }
            ],
            "columnListUuid": row_uuids[0],
            "columnUuid": SecureRandom.uuid,
            "columnRatio": 50,
            "hasCaption": true,
            "caption": "Last ##{comment_face}"
          }
        },
        {
          "uuid": SecureRandom.uuid,
          "type": "IMAGE",
          "groupUuid": group_uuids[0],
          "groupType": "IMAGE",
          "payload": {
            "images": [
              {
                "name": download_link,
                "url": download_link
              }
            ],
            "columnListUuid": row_uuids[0],
            "columnUuid": SecureRandom.uuid,
            "columnRatio": 50,
            "hasCaption": true,
            "caption": "Current ##{comment_face}"
          }
        },
        {
          "uuid": SecureRandom.uuid,
          "type": "TITLE",
          "groupUuid": group_uuids[1],
          "groupType": "QUESTION",
          "payload": {
            "columnListUuid": row_uuids[1],
            "columnUuid": col_uuids[1],
            # "columnRatio": 50,
            "safeHTMLSchema": [
              [
                "Do you like the current ##{comment_face} more or less than last season's?"
              ]
            ]
          }
        },
        {
          "uuid": SecureRandom.uuid,
          "type": "LINEAR_SCALE",
          "groupUuid": group_uuids[1],
          "groupType": "LINEAR_SCALE",
          "payload": {
            "isRequired": false,
            "start": RATING_MIN,
            "end": RATING_MAX,
            "step": 1,
            "columnListUuid": row_uuids[1],
            "columnUuid": col_uuids[1],
            # "columnRatio": 50,
            # "hasCenterLabel": true,
            # "centerLabel": "Mid",
            "hasLeftLabel": true,
            "leftLabel": "Less",
            "hasRightLabel": true,
            "rightLabel": "More"
          }
        }
      ]

    blocks << {
      "uuid": SecureRandom.uuid,
      "type": "DIVIDER",
      "groupUuid": SecureRandom.uuid,
      "groupType": "DIVIDER",
      "payload": {}
    }

    blocks
  end
end

def calculate_hof_blocks(comment_faces, mention_ids)
  # comment_faces = [comment_faces.to_a[0]].to_h

  blocks =
    [
      {
        "uuid": SecureRandom.uuid,
        "type": "TITLE",
        "groupUuid": SecureRandom.uuid,
        "groupType": "TITLE",
        "payload": {
          "columnListUuid": SecureRandom.uuid,
          "columnUuid": SecureRandom.uuid,
          "safeHTMLSchema": [
            [
              "Hall of Fame Voting"
            ]
          ]
        }
      },
      {
        "uuid": SecureRandom.uuid,
        "type": "TEXT",
        "groupUuid": SecureRandom.uuid,
        "groupType": "TEXT",
        "payload": {
          "columnListUuid": SecureRandom.uuid,
          "columnUuid": SecureRandom.uuid,
          "safeHTMLSchema": [
            [
              "Here you can help us pick which seasonal comment face will get added to the Hall of Fame and stay as a permanent comment face. Note: this is not a direct vote."
            ]
          ]
        }
      },
      {
        "uuid": SecureRandom.uuid,
        "type": "TEXT",
        "groupUuid": SecureRandom.uuid,
        "groupType": "TEXT",
        "payload": {
          "columnListUuid": SecureRandom.uuid,
          "columnUuid": SecureRandom.uuid,
          "safeHTMLSchema": [
            [
              "You have #{POINTS_TO_ALLOCATE} points to allocate amongst the various comment faces. You may allot up to a maximum of #{POINTS_ALLOTTED_MAX} points per comment face."
            ]
          ]
        }
      },
      {
        "uuid": SecureRandom.uuid,
        "type": "CALCULATED_FIELDS",
        "groupUuid": mention_ids[:points][:block_group_uuid],
        "groupType": "CALCULATED_FIELDS",
        "payload": {
          "calculatedFields": [
            {
              "uuid": mention_ids[:points][:field_uuid],
              "type": "NUMBER",
              "value": POINTS_TO_ALLOCATE,
              "name": mention_ids[:points][:name]
            }
          ]
        }
      },
      {
        "uuid": SecureRandom.uuid,
        "type": "TEXT",
        "groupUuid": SecureRandom.uuid,
        "groupType": "TEXT",
        "payload": {
          "safeHTMLSchema": [
            ["Points: "],
            [
              "@#{mention_ids[:points][:name]}",
              [["tag", "span"], ["mention", mention_ids[:points][:mention_uuid]]]
            ],
          ]
        }
      },
    ]
  blocks +=
    comment_faces.each_slice(HOF_COMMENT_FACES_PER_ROW).flat_map do |cfs|
      row_uuid = SecureRandom.uuid # probably need to batch in 5's
      cfs.flat_map do |comment_face, download_link|
        group_uuid = SecureRandom.uuid
        col_uuid = SecureRandom.uuid
        input_uuid = SecureRandom.uuid
        [
          {
            "uuid": SecureRandom.uuid,
            "type": "IMAGE",
            "groupUuid": SecureRandom.uuid,
            "groupType": "IMAGE",
            "payload": {
              "images": [
                {
                  "name": download_link,
                  "url": download_link
                }
              ],
              "columnListUuid": row_uuid,
              "columnUuid": col_uuid,
              "columnRatio": 100 / HOF_COMMENT_FACES_PER_ROW,
              # "hasCaption": true,
              # "caption": "Current ##{comment_face}"
            }
          },
          {
            "uuid": SecureRandom.uuid,
            "type": "TITLE",
            "groupUuid": SecureRandom.uuid,
            "groupType": "QUESTION",
            "payload": {
              "columnListUuid": row_uuid,
              "columnUuid": col_uuid,
              "columnRatio": 100 / HOF_COMMENT_FACES_PER_ROW,
              "safeHTMLSchema": [
                [
                  "##{comment_face}"
                ]
              ]
            }
          },
          {
            "uuid": input_uuid,
            "type": "LINEAR_SCALE",
            "groupUuid": group_uuid,
            "groupType": "LINEAR_SCALE",
            "payload": {
              "isRequired": false,
              "start": 0,
              "end": POINTS_ALLOTTED_MAX,
              "step": 1,
              "hasDefaultAnswer": true,
              "defaultAnswer": 0,
              "columnListUuid": row_uuid,
              "columnUuid": col_uuid,
              "columnRatio": 100 / HOF_COMMENT_FACES_PER_ROW
            }
          },
          {
            "uuid": SecureRandom.uuid,
            "type": "CONDITIONAL_LOGIC",
            "groupUuid": SecureRandom.uuid,
            "groupType": "CONDITIONAL_LOGIC",
            "payload": {
              "updateUuid": nil,
              "logicalOperator": "AND",
              "conditionals": [
                {
                  "uuid": SecureRandom.uuid,
                  "type": "SINGLE",
                  "payload": {
                    "field": {
                      "uuid": group_uuid,
                      "type": "INPUT_FIELD",
                      "questionType": "LINEAR_SCALE",
                      "blockGroupUuid": group_uuid,
                      "title": "##{comment_face}"
                    },
                    "comparison": "GREATER_OR_EQUAL_THAN",
                    "value": 0
                  }
                }
              ],
              "actions": [
                {
                  "uuid": SecureRandom.uuid,
                  "type": "CALCULATE",
                  "payload": {
                    "calculate": {
                      "field": {
                        "uuid": mention_ids[:points][:field_uuid],
                        "type": "CALCULATED_FIELD",
                        "questionType": "CALCULATED_FIELDS",
                        "blockGroupUuid": mention_ids[:points][:block_group_uuid],
                        "title": mention_ids[:points][:name],
                        "calculatedFieldType": "NUMBER"
                      },
                      "operator": "SUBTRACTION",
                      "value": {
                        "uuid": group_uuid,
                        "type": "INPUT_FIELD",
                        "questionType": "LINEAR_SCALE",
                        "blockGroupUuid": group_uuid,
                        "title": "##{comment_face}"
                      }
                    }
                  }
                }
              ]
            }
          },
        ]
      end + [
        {
          "uuid": SecureRandom.uuid,
          "type": "DIVIDER",
          "groupUuid": SecureRandom.uuid,
          "groupType": "DIVIDER",
          "payload": {}
        },
      ]
    end

  blocks = blocks.each_with_index.sort_by do |block, index|
    [block[:type] == "CONDITIONAL_LOGIC" ? 1 : 0, index]
  end.map(&:first)

  too_many_points_uuid = SecureRandom.uuid
  blocks +=
    [
      {
        "uuid": SecureRandom.uuid,
        "type": "CONDITIONAL_LOGIC",
        "groupUuid": SecureRandom.uuid,
        "groupType": "CONDITIONAL_LOGIC",
        "payload": {
          "updateUuid": nil,
          "logicalOperator": "AND",
          "conditionals": [
            {
              "uuid": SecureRandom.uuid,
              "type": "SINGLE",
              "payload": {
                "field": {
                  "uuid": mention_ids[:points][:field_uuid],
                  "type": "CALCULATED_FIELD",
                  "questionType": "CALCULATED_FIELDS",
                  "blockGroupUuid": mention_ids[:points][:block_group_uuid],
                  "title": mention_ids[:points][:name],
                  "calculatedFieldType": "NUMBER"
                },
                "comparison": "LESS_THAN",
                "value": 0
              }
            }
          ],
          "actions": [
            {
              "uuid": SecureRandom.uuid,
              "type": "HIDE_BUTTON_TO_DISABLE_COMPLETION"
            },
            {
              "uuid": SecureRandom.uuid,
              "type": "SHOW_BLOCKS",
              "payload": {
                "showBlocks": [
                  too_many_points_uuid
                ]
              }
            }
          ]
        }
      },
      {
        "uuid": too_many_points_uuid,
        "type": "TEXT",
        "groupUuid": SecureRandom.uuid,
        "groupType": "TEXT",
        "payload": {
          "isHidden": true,
          "safeHTMLSchema": [
            [
              "You have allotted too many points"
            ]
          ]
        }
      },
    ]

  blocks
end

def calculate_other_questions_blocks
  seasonal_wildcard_group_uuid = SecureRandom.uuid
  [
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "QUESTION",
      "payload": {
        "safeHTMLSchema": [
          [
            "How do you like this format over the Google Forms one?"
          ]
        ]
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "LINEAR_SCALE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "LINEAR_SCALE",
      "payload": {
        "isRequired": false,
        "start": 0,
        "end": 10,
        "step": 1,
        "hasLeftLabel": true,
        "leftLabel": "It sucks",
        "hasCenterLabel": true,
        "centerLabel": "Mid",
        "hasRightLabel": true,
        "rightLabel": "It's great"
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "QUESTION",
      "payload": {
        "safeHTMLSchema": [
          [
            "Do you have any feedback / ideas about this new survey format?"
          ]
        ]
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "TEXTAREA",
      "groupUuid": SecureRandom.uuid,
      "groupType": "TEXTAREA",
      "payload": {
        "isRequired": false,
        "placeholder": ""
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "PAGE_BREAK",
      "payload": {
        "safeHTMLSchema": [
          ["Please double check your answers. You won't be able to easily edit them after you hit submit."]
        ]
      }
    }
  ]
end

def calculate_thank_you_page_blocks(title, mention_ids)
  [
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "PAGE_BREAK",
      "payload": {
        "safeHTMLSchema": [
          ["Thank you for filling out the #{title}."]
        ]
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "PAGE_BREAK",
      "payload": {
        "safeHTMLSchema": [
          ["If you wish to change your answers, just do the form again and mod mail us your respondent id so that we can double check everything. We'll take your most recent submission."],
        ]
      }
    },
    {
      "uuid": SecureRandom.uuid,
      "type": "TITLE",
      "groupUuid": SecureRandom.uuid,
      "groupType": "PAGE_BREAK",
      "payload": {
        "safeHTMLSchema": [
          ["Your respondent id is "],
          [
            "@Respondent ID",
            [["tag", "span"], ["mention", mention_ids[:respondent_id][:uuid]]]
          ]
        ]
      }
    }
  ]
end

def get_survey_title(year, season)
  next_season = @github_service.get_next_season(year, season)
  "#{next_season[1].capitalize} #{next_season[0]} Seasonal Face Survey (for #{season.capitalize} #{year})"
end

main ARGV[0].to_i, ARGV[1]

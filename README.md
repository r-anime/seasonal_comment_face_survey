# seasonal_comment_face_survey

# Local Dev Setup

1. Install ruby. Newest should be fine, but the version is in .tool-versions. As u/baseballlover723 is currently writing this, it's ruby 3.4.7 and he installed it via [asdf](https://asdf-vm.com/)
2. Install bundler. Bundler is the dependency management tool, it probably comes stock, and the version doesn't matter, as any modern version will install the project specific version automatically.
3. Install dependencies. Run `bundle install` in the root directory. There shouldn't be anything too crazy in there that should require extra deps to be installed (except maybe postgres, but you need postgres, duh)
4. Start external dependencies (Postgres & RabbitMQ)
5. Run the project. `bundle exec ruby app.rb`. Bundle exec is needed here to ensure that it loads the right reddit library gem.
6. App should be running. You should see `Successfully connected to postgres`, `Successfully authed to reddit`, and `✅ Listening on ...` if everything is sucessful.

## Docker Compose Dev Setup
1. `docker compose build --pull`
2. `docker compose up --build seasonal_comment_face_survey`
3. App should be running. You should see Sinatra / Puma start up if everything is successful.

## Nominations script

This is the script to parse and categorize the nominations into a csv.

Currently, you need to grab the reddit comment post by adding `.json` to the end of the url

save that in `reddit.json` in the root of the project

then run `ruby generate_comments.rb` or `docker compose up --build seasonal_comment_face_nominations` (it should also generate a cache file)

it will generate `comment_faces.csv`

then import that file into google sheets

use replace current sheet to keep formatting

you will need to find and replace `'=` with `=` (searching within formulas) to get the images to load properly

The algorithm is to keep track of the last face code (including in the link text directly), and then grabbing the link.
It should process replies recursively, but not quoted links.
It should process any link that isn't a reddit link (including album's and videos).

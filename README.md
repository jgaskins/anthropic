# anthropic

Client for the Anthropic API. Supports tool use and running those tools automatically.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     anthropic:
       github: jgaskins/anthropic
   ```

2. Run `shards install`

## Usage

```crystal
require "anthropic"
```

The main entrypoint is via the `Anthropic::Client`. You can instantiate it explicitly with an API key:

```crystal
claude = Anthropic::Client.new("sk-and-api-03-asdfasdfasdf")
```

Or you can omit the API key to automatically read it from the `ANTHROPIC_API_KEY` environment variable:

```crystal
claude = Anthropic::Client.new
```

Next, use the `Anthropic::Messages#create` method to send your prompt:

```crystal
response = claude.messages.create(
  # Pass a string representing the model name, or retrieve the full model
  # name via the shorthand with Anthropic.model_name.
  model: Anthropic.model_name(:sonnet),

  # Define a system prompt if you want to give the AI a persona to use or some
  # instructions on how to respond to the prompt.
  system: "You are an expert in the Crystal programming language",

  # You can pass the full list of messages, including messages it gave you
  # back.
  messages: [
    Anthropic::Message.new("What makes Crystal the best programming language?")
  ],

  # The maximum number of tokens the AI will try to respond with. Keep this low
  # if you're feeding untrusted prompts.
  max_tokens: 4096,

  # A floating-point value between 0.0 and 1.0 representing how creative the
  # response should be. Lower values (closer to 0.0) will be more deterministic
  # and should be used for analytical prompts. Higher values (closer to 1.0)
  # will be more stochastic.
  temperature: 0.5,

  # You can optionally pass an `Array` of tools to give the client a way to run
  # custom code in your app. See below for additional information on how to
  # define those. The more tools you pass in with a request, the more tokens the
  # request will use, so you should keep this to a reasonable size.
  #
  # By default, no tools are included.
  tools: [
    GitHubUserLookup,
    GoogleDriveSearch.new(google_oauth_token),
  ],

  # Uncomment the following line to avoid automatically running the tool
  # selected by the model.
  # run_tools: false,

  # Limit the token selection to the "top k" tokens. If you need this
  # explanation, chances are you should use `temperature` instead. That's not a
  # dig — I've never used it myself.
  # top_k: 10,

  # P value for nucleus sampling. If you're dialing in your prompts with the
  # `temperature` argument, you should ignore this one. I've never used this
  # one, either.
  # top_p: 0.1234,
)
```

You can also pass images to the model:

```crystal
puts claude
  .messages
  .create(
    # You should generally use the Haiku model when dealing with images since
    # they tend to consume quite a few tokens.
    model: Anthropic.model_name(:haiku),
    messages: [
      Anthropic::Message.new(
        content: Array(Anthropic::MessageContent){
          # Images are base64-encoded and sent to the model
          Anthropic::Image.base64(:jpeg, File.read("/path/to/image.jpeg")),
          Anthropic::Text.new("Describe this image"),
        },
      ),
    ],
    max_tokens: 4096,
    # Using a more deterministic response about the image
    temperature: 0.1,
  )
```

### Defining tools

Tools are objects that the Anthropic models can use to invoke your code. You
can define them easily with a `struct` that inherits from
`Anthropic::Tool::Handler`.

```crystal
struct GitHubUserLookup < Anthropic::Tool::Handler
  # Define any properties required for this tool as getters. Claude will
  # provide them if it can based on the user's question.

  # The username/login for the GitHub user, used to fetch the user from the
  # GitHub API.
  getter username : String

  # This is the description that lets the model know when and how to use your
  # code. It's basically the documentation the model will use. The more
  # descriptive this is, the more confidence the model will have in invoking
  # it, but it does consume tokens.
  def self.description
    <<-EOF
      Retrieves the GitHub user with the given username. The username may also
      be referred to as a "login". The username can only contain letters,
      numbers, underscores, and dashes.

      The tool will return the current data about the GitHub user with that
      username. It should be used when the user asks about that particular
      GitHub user. It will not provide information about GitHub repositories
      or any issues, pull requests, commits, or other content on GitHub created
      by that GitHub user.
      EOF
  end

  # This is the method the client will use to invoke this tool. The return value
  # of this method will be serialized as JSON and sent over the wire as the
  # tool-use result
  def call
    User.from_json HTTP::Client.get(URI.parse("https://api.github.com/users/#{username}")).body
  end

  # The definition for the value we want to send back to the model. Every
  # property specified here will consume tokens, so only define getters that
  # will provide useful context to the model.
  struct User
    include JSON::Serializable

    getter login : String
    getter name : String
    getter company : String?
    getter location : String
    getter bio : String?
    getter public_repos : Int64
    getter public_gists : Int64
    getter followers : Int64
    getter following : Int64
  end
end
```

You can also define tools without inheriting from `Anthropic::Tool::Handler`. That type simply implements the following API on the tool object (instance or type) being passed in:

- `name : String`
- `description : String`
- `json_schema`, which returns a `to_json`-able object
- `parse`, which returns a `call`-able object which returns a `to_json`-able object

Here is an example of a tool that searches a user's Google Drive (via the [`jgaskins/google`](https://github.com/jgaskins/google) shard) using the provided query. Claude will generate the query and pass it to the tool, 

```crystal
require "google"
require "google/drive"

record GoogleDriveSearch, token : String do
  GOOGLE = Google::Client.new(
    client_id: ENV["GOOGLE_CLIENT_ID"],
    client_secret: ENV["GOOGLE_CLIENT_SECRET"],
    redirect_uri: URI.parse("https://example.com/oauth2/google"),
  )

  def description
    "Search Google for a user's documents with the given search query. You must use the Google Drive API query string format."
  end

  def name
    "GoogleDriveSearch"
  end

  def json_schema
    # The `json_schema` class method is provided on all `JSON::Serializable`
    # types by the `spider-gazelle/json-schema` shard.
    Query.json_schema
  end

  def parse(json : String)
    query = Query.from_json json
    query.search = self
    query
  end

  def call(query : String)
    files = GOOGLE
      .drive
      .files
      .list(
        token: token,
        q: "(#{query}) and mimeType contains 'application/vnd.google-apps'",
        limit: 10,
      )
      .to_a

    array = Array(FileInfo).new(files.size)
    # Requires this PR to be released, or the equivalent monkeypatch:
    #   https://github.com/crystal-lang/crystal/pull/14837
    WaitGroup.wait do |wg|
      mutex = Mutex.new
      files.each do |file|
        wg.spawn do
          file_info = FileInfo.new(
            id: file.id,
            name: file.name,
            content: GOOGLE.drive.files.export(file, "text/plain", token, &.gets_to_end),
            link: file.web_view_link,
          )

          mutex.synchronize do
            array << file_info
          end
        end
      end
    end

    array
  end

  struct FileInfo
    include JSON::Serializable

    getter id : String
    getter name : String
    getter content : String
    getter link : String

    def initialize(@id, @name, @content, @link)
    end
  end

  struct Query
    include JSON::Serializable

    getter query : String
    @[JSON::Field(ignore: true)]
    protected property! search : GoogleDriveSearch

    def call
      search.call(query)
    end
  end
end
```

See the example code above to find out how to pass them to the model.

## Contributing

1. Fork it (<https://github.com/jgaskins/anthropic/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer

## The Chocolate Shell and Chain of Responsibility Design Patterns


Let's assume a program that fetches and parses data from Rescuetime's API:


```
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime)
    response = request(datetime)

    parsed_rows = response.fetch('rows').map do |row|
      {
        date:                  ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
        time_spent_in_seconds: row[1],
        number_of_people:      row[2],
        activity:              row[3],
        category:              row[4],
        productivity:          row[5]
      }
    end
  end

  def self.request(datetime)
    formatted_date = datetime.strftime('%Y-%m-%d')
    url =
      "#{ENV['RESCUETIME_API_URL']}?"\
      "key=#{ENV['RESCUETIME_API_KEY']}&"\
      "restrict_begin=#{formatted_date}&"\
      "restrict_end=#{formatted_date}&"\
      'perspective=interval&'\
      'resolution_time=minute&'\
      'format=json'

    HTTParty.get(url)
  end
end

```
*[ex1 and tests](http://github.com)*

This is nice enough. Depending on coding style we may extract some methods, but we just intuitively like it and all think it's easy enough to work with.  The flog score is 21.2 -- pretty good.  The business logic is clear. The tests clearly describe the behavior.  We deem this acceptably clean code, and release the software.

```
* A brief note on Flog *

Flog is a ruby gem that uses ABC (assignments, branching and conditionals) to measure complexity in a piece of code.  I don't use it an absolute judgement for complexity, but it is a nice measurement to supplement personal heuristics.
```

Graceful error handling and capturing metrics become important. The more data we have the more the company can base change from empirical data.  More users have been complaining about seeing stack traces when using the app -- this is bad on a number of levels.  We make a new release:

```
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime, logger)
    run_start_time = Time.now

    begin
      url = build_url(datetime)
    rescue => e
      logger.fatal("Problem parsing url: #{e.inspect}")
			return
    end

    start_time = Time.now
    begin
      response = HTTParty.get(url)
    rescue => e
      logger.fatal("Http failed: #{e.inspect}")
			return
    end

    logger.info("duration of http request: #{Time.now - start_time}")

    start_time = Time.now
    begin
      parsed_rows = parse_response_to_rows(response)
    rescue => e
      logger.fatal("Parsing date failed: #{e.inspect}")
    end

    logger.info("duration of data parsing: #{Time.now - start_time}")
    logger.info("Rescuetime fetch completed in: #{Time.now - run_start_time}")

    parsed_rows
  end

  def self.build_url(datetime)
	raise if datetime.nil?
    
    formatted_date = datetime.strftime('%Y-%m-%d')

	api_url = ENV['RESCUETIME_API_URL']
	api_key = ENV['RESCUETIME_API_KEY']
	raise if api_url.nil? || api_key.nil?

    "#{api_url}?"\
    "key=#{api_key}&"\
    "restrict_begin=#{formatted_date}&"\
    "restrict_end=#{formatted_date}&"\
    'perspective=interval&'\
    'resolution_time=minute&'\
    'format=json'
  end

  def self.parse_response_to_rows(response)
	timezone = ENV['RESCUETIME_TIMEZONE']
	raise "no timezone" if timezone.nil?

    response.fetch('rows').map do |row|
      {
        date:                  ActiveSupport::TimeZone[timezone].parse(row[0]).utc.to_s,
        time_spent_in_seconds: row[1],
        number_of_people:      row[2],
        activity:              row[3],
        category:              row[4],
        productivity:          row[5]
      }
    end
  end
end
```
*[ex2 and tests](http://github.com)*

Our code has become close to unreadable.  Our control flow is hard to follow.  The business logic is hidden behind a mass of log statements and rescue blocks.  Our tests, in a silver lining, break out and describe the failure cases we handle.  While this is nice, I still wouldn't want to be the next developer in here.

#### The Chocolate Shell and the Creamy Center

About a year ago, Michael Feathers introduced me to a concept called "the chocolate shell and the creamy center". The concept has two points: first, that error handling and logging are separate responsibilities from business logic.  It should be encapsulated and abstracted in what he called "the chocolate shell".  Second, the rest of the code should just assume data is going to be in a good state to be used -- "the creamy center".

The idea has some interesting points that could aid in refactoring our code.  If the data is pure, then the code simplifies and directly expresses business logic instead of being peppered with logs and rescues.  Our tests would also be able to purely express only one path at a time, too.

#### A simple implementation: the begin/rescue shell

ex3

Show the change to the tests, too.

7. Basic logging: Introduce the Chain of Responsibility

The Chain of Responsibility pattern is a lot like a linked list of command objects.

Like the command pattern, every object will have the same public method signature.  That means a single public method with the same airity, no matter what the object will do.

Our design is being driven based on our needs to monitor or handle failure.

Also show how it keeps the business logic cleaner and the failure testing to one object.

ex4

8. Advanced Logging and Exception Handling

ex5

Custom per action, also communicating how the system behaves for failure.

This could have a ExecutionFactory that takes the list of actions as an argument and then the tests will test real configuration.

9. Adding Stability Patterns

10. Exploring in other languages








## Error Handling the Sane Way With The Supervisor Pattern

_The Supervisor Pattern is a programming pattern where you organize behavior into cohesive, scoped units of work and put error handling and logging in a single place for that unit.  This pattern is inspired by Erlang's approach to handling failure, but also takes inspiration from Go and Javascript.  This article describes failure strategies, and potential implementations with examples so others can more easily incorporate sane error supervision in their own applications._

### Table of Contents


### Tell me if this seems familiar

Let's assume a program that fetches and parses data from Rescuetime's API:

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime)
	response = request(datetime)

	response.fetch('rows').map do |row|
	  {
		date:				  ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
		time_spent_in_seconds: row[1],
		number_of_people:	  row[2],
		activity:			  row[3],
		category:			  row[4],
		productivity:		  row[5]
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
[ex1 and tests](http://github.com)

This is nice enough. The business logic is clear. The tests clearly describe the behavior.

Since our system and userbase is small, we don't pay much attention to error handling.  We're more focused on delivering business value for the happy path.  We setup an exception notifier like Airbrake or Honeybadger and release the software.

Not too soon after release, our exception reporting is kicking in.  First, we forgot to set the right environment variables for the Rescuetime URL on our latest deploy, so we add guard statements:

```ruby
def self.request(datetime)
	formatted_date = datetime.strftime('%Y-%m-%d')
	return if ENV['RESCUETIME_API_URL'].empty? || ENV['RESCUETIME_API_KEY'].empty?
    # ...continue
```

Since request can now return nil, we add a guard to the parsing:

```ruby
def self.fetch(datetime)
	response = request(datetime)
	return unless response
	
	response.fetch('rows').map do |row|
	  {
		date: ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
		# ...continue
```

The consumer (here it is some sort of HTTP client) has to also be able to respond to nil:

```ruby
def get
	response = RescuetimeFetch.request(params[:datetime])
	
	if response.nil?
		return []
	else
		response
	end
end
```

Also, datetime is coming from the outside world, and we've seen lots of error reports with the ```params[:datetime]``` field full of bad data, and we want to make sure it is something parsable into a formatted date:

```ruby
begin
	formatted_date = DateTime.parse(datetime).strftime('%Y-%m-%d')
rescue => e
	return { error: "not a real date" }
end

return if ENV['RESCUETIME_API_URL'].empty? || ENV['RESCUETIME_API_KEY'].empty?
# ...continue
```

Since this is something from the user, we want them to have information in order to make a decision on what to do.  We don't change the API url information though since that is set in the configuration of the environment -- we don't want the user to set the api url.

This now becomes:

```ruby
def self.fetch(datetime)
	response = request(datetime)
	return unless response 
	return response if response[:error]
	
	response.fetch('rows').map do |row|
	  {
		date: ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
		# ...continue
```

And whatever is consuming our module:

```ruby
# In the consumer

def get
	response = RescuetimeFetch.request(params[:datetime])
	
	if response.nil? || response[:error]
		return response[:error] || "We're sorry, something went wrong."
	else
		response
	end
end
```

At this point, let's look at the entire project:

```ruby
require 'fetch_rescuetime_data'

module Consumer
  def get
    response = RescuetimeFetch.request(params[:datetime])

    if response.nil? || response[:error]
      return response[:error] ||
        "We're sorry, something went wrong."
    else
      response
    end
  end
end
```

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'

class RescuetimeData
  def self.fetch(datetime)
    response = request(datetime)
    return unless response
    return response if response[:error]

    response.fetch('rows').map do |row|
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
    begin
      formatted_date = Time.parse(datetime).strftime('%Y-%m-%d')
    rescue => e
      return { error: "not a real date" }
    end

    return if ENV['RESCUETIME_API_URL'].empty? || ENV['RESCUETIME_API_KEY'].empty?

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
[ex2 and tests](http://github.com)

What we've done is a very natural progression in most projects: get the happy path out the door, setup exception notification, and fix the errors as they come in.

There is nearly the same amount of error handling code as we do happy path code, and we are only handling a fraction of all possible errors.  Our module's post-conditions are complex:  sometimes we return nil, an object that has a message for the user or the real value. Sometimes we use begin/rescue for flow control.  Sometimes we use conditionals -- and this is only the first round of fixes based on failure.

The error handling we did put in place, though, allows graceful degredation of certain features to give the user something to do.  The negative to this, though, is that by capturing errors and not re-raising them, we lose the transparency and metrics exception notification provides.

### How To Handle Failure

Unless we stop and consider some basic error handling abstractions, more modules will be added to the system and are doomed to repeat the above process.  The larger the system gets, the more we will be unable to safely and clearly apply many levels of fault tolerance.  What we need is to learn about how to handle failure a more mature way. 

> While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.
> 
> Craig Stuntz

[src](http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/)

#### Go

> Any function that does I/O, for example, must confront the possiblity of error, and only a naive programmer believes a simple read or write cannot fail.  Indeed, it's when the most reliable operations fail unexpectedly that we most need to know why.

> Alan A. A. Donovan and Brian W. Kernighan

[src](http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS)

##### Explicit Errors

In Go, ```error``` is built-in, ordinary value.  The creators of Go saw that exceptions add complexity.  Throws, rescues, catches and raises pollute the control flow.  For Go, errors are a natural part of a healthy program running in production and should be consciously handled.

Instead of blocks that scope code execution for protection -- like a begin/rescue in Ruby -- Go uses normal control flow mechanisms like if and return to process errors:

```go
f, err := os.Open("filename.ext")
if err != nil {
    log.Fatal(err)
}
```
[src](http://blog.golang.org/error-handling-and-go)

Explicitly returning errors demands the error receives attention.  Coupled with Go's static typing, errors need to be explicitly ignored.  As an added benefit, the user will less likely be randomly subjected to stack traces. 

While Go forces the developer to face errors a natural running system could produce, there is still a ```panic```, which is conventionally, used when when the system is totally broken and in an unrecoverable format.

##### Communicating With Error messages

The Go community established a convention for error messages that make it easy for operators to track down what went wrong in a casual chain with strings.  Let's say we wanted to craft an error message for an HTTP timeout failure for the Rescuetime code.  In Go, it may be structured like this:

```go
rescuetime: fetch: http timeout: the url of http://rescuetime-api.com timed out at 5 seconds
```

A chain of strings is an easy data structure to scan or grep, and gives a uni-directional view leading to the failure.  While we may want to add some more information like variable values or line numbers, the bigger message from the structure of the message is that errors are meant to teach a human what went wrong.

#### Erlang

> The best example of Erlang's robustness is the often-reported nine nines (99.9999999 percent) of availability offered on the Ericsson AXD 301 ATM switches, which consist of more than a million lines of Erlang code.
> 
> Fred Hebert

[src](http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG)

Erlang is known as a language to build highly scalable, fault tolerant systems of a massively distributed nature.  Let's explore why Erlang is so good at dealing with failure.

Let's first look at this piece of code and analyze what error handling features it shows us:

```erlang
-module(sup).
-export([start/2, start_link/2, init/1, loop/1]).

start(Mod,Args) ->
  spawn(?MODULE, init, [{Mod, Args}]).

start_link(Mod,Args) ->
  spawn_link(?MODULE, init, [{Mod, Args}]).

init({Mod,Args}) ->
  process_flag(trap_exit, true),
  loop({Mod,start_link,Args}).

loop({M,F,A}) ->
  Pid = apply(M,F,A),
  receive
    {'EXIT', _From, shutdown} ->
      exit(shutdown); % will kill the child too
    {'EXIT', Pid, Reason} ->
      io:format("Process ~p exited for reason ~p~n",[Pid,Reason]),
      loop({M,F,A})
  end.
```
[src](learnyousomeerlang)

What we see above is a simple example of a supervisor.

##### Process Isolation

A large part of Erlang's ability to keep operating despite failure is process isolation.  A process in Erlang is responsible for doing a discrete unit of work in total isolation -- no memory sharing, no locks and no dependent communication with other processes.

Erlang/OTP applications are usually represented as a tree structure, where one process, known as a supervisor, will oversee the worker processes.

The supervisor is responsible for observing and orchestrating the workers, which should do the bulk of the business processing.  When a process encounters an issue, Erlang's philosophy is to let it crash, or fail fast. Erlang/OTP systems _expect_ error to occur and build handling into the supervisor.

> Engineers are not conditioned to embrace their ability to respond to emergencies; they aim to avoid them altogether
> 
> John Allspaw

[src](http://queue.acm.org/detail.cfm?id=2353017)

Coming from a defensive programming mindset, this may seem outright dangerous.  But Erlang believes failing processes quickly helps avoid data corruption and transient bugs that commonly cause system crashes at scale, and forces confronting error earlier rather than later and reducing the fear of system failures.

##### Links and Monitors

A Link is a bidirectional bond between two processes.  When a process crashes, the linked processes will terminate, or trap the exit if it wants to live.  The message received is an exit, the process identifier, or PID, of the terminated process, and a reason for failure:

```erlang
{'EXIT', FromPid, Reason}
```

Erlang provides Monitors for unidirectional observation in case of failure.  A process can be monitored like this:

```erlang
erlang:monitor(process, MonitoredPid)
```

```process``` is an atom, or a constant whose only value is their own name.  The ```MonitoredPid``` is a variable that has been bound to the process identifier that we'd like to monitor.

When the monitored process terminates, the monitor will receive this data structure:

```erlang
{'DOWN', Ref, process, MonitoredPid, Reason}
```
[src](http://erlang.org/doc/reference_manual/processes.html)

Among other things, the monitor will receive a down signal with a reason and the pid that went down.

A supervisor will usually use links and monitors with spawned child worker processes, and depending on the message and reason, will know what to do in case of failure, such as restarting the process.

Keeping error handling in the supervisor encapsulates logic around failure, and reduces the complexity error handling adds to other parts of the application.

### Failure Strategies and Considerations

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

[src](http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/)

##### Errors for the System, and Errors for the User

Two segments will see error: the system and engineers, and the public.  Make sure whatever is seen is appropriate.

For the public, they should not see stack traces.  They should be given a good error message and information on what they can do in the meantime.

For the system and engineers, make sure data is structured in a way that makes diagnosis and problem analysis easy.  Go gives a causal string for high-level understanding and Erlang gives a list of tuples as a strack trace for programatic analysis.

For either party, the goal is a simple user experience.

##### Error Handling Changes System Convention

> You can try to prevent bugs all you want, but most of the time, some will still creep in.  And even if by some miracle your code doesn't have any bugs, nothing can stop the eventual hardware failure.  Therefore, the idea is to find good ways to handle errors and problems, rather than trying to prevent them all.
> 
> Fred Hebert

[src](http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG)

Error handling is foundational in both Go's and Erlang's designs and philosophies.  Ignoring failure is close to impossible.

Handling failure is the central driver to the architecture of Erlang/OTP applications.  Errors will *ALWAYS* happen, and the sooner they are faced the more stable the system will become.

If error handling is peppered in after the system has matured, expect expensive refactorings to become fault tolerant, and in the meantime, enjoy the complexity and uncertaintly of incomplete, unorganized error handling.

##### Localized, Uniform Error Handling Simplifies Flow Control

In an application that is defensively programmed, there is a plethora of ways to signal failure.  Maybe a guard statement is used, or an exception is raised or an error is thrown and caught.  The varience and multiple levels of error handling logic complicates systems.

Erlang supervisors are the really the single place where errors are caught and special logic is applied.  The workers fail fast and are clear of error handling logic, or flow control in case of failure.

Go simplifies this by having an error be a recognized type that flow control would be applied to, meaning there is only one way errors will be handled for flow control.  For most purposes, an error is an error.

If it prevents the system from operating on the happy path, fail fast to one place in one way and depend on the error handler to know what to do.

Failing in one way and having that failure handled in one place encapsulates what a failure is, and how failure to handle it.

### Applying the Lessons

> Proper error handling is an essential requirement of good software.
> 
> Andrew Gerrand

[src](http://blog.golang.org/error-handling-and-go)

Let's rewrite our Rescuetime code with these principles:

```ruby
require 'boundary'
require 'rescuetime/fetch'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error = Boundary.run(error_config) do
      Rescuetime::Fetch.call(datetime)
    end
  end

  private

  def error_config
    [
      { matcher: '# key not found', i18n: :invalid_api_key },
      { matcher: 'format_date', i18n: :invalid_date }
    ]
  end
end
```                                                      

Think of the consumer as an HTTP client.  Like in Go, two variables are returned: the result, or an error.  If there is no error, the value is nil.  I didn't really do much with the error here, but if it is an http application, assume the view will know how to render an error variable.

Here's what the Boundary looks like:

```ruby
require 'boundary/error'                          
require 'boundary/logger'

module Boundary
  def self.run(error_configuration = [])
    begin
      [yield, nil]
    rescue => e
      error = Error.new(e, error_configuration)
      Logger.error(error.system_error_information)

      [nil, error.user_error_information]
    end
  end
end
```

The ```Boundary``` is the only place error handling exists.  It is localized only to the Rescuetime fetch call.  If an error is rescued, we log system specific information for developers to see and we return information for the consumer to use. 

The ```Error``` abstraction is responsible for composing errors for a specific consumer.

```ruby
require 'pretty_backtrace'                    
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

module Boundary
  class Error < RuntimeError
    attr_reader :error
  
    def initialize(error, error_configs)
      @error = error   
      @error_configs = error_configs
    end

    def default_error_config
      { i18n: :default }
    end

    def system_error_information
      error.backtrace[0...5]
    end

    def user_error_information
      i18n
    end

    private

    def i18n
      backtrace = error.backtrace[0...5].join(',')

      @error_configs.find(lambda{ default_error_config }) do |c|
        backtrace.include?(c[:matcher])
      end[:i18n]
    end
  end
end                                                             
```

For the system side, I used the pretty_backtrace gem which returns the backtrace with line numbers, code and variable values, and I limit it to the first 5 lines to help developers parse the information.

I didn't explore it much further, but the error itself should probably be returned, and more exploration to the amount and format of the backtrace is another avenue for good ideas.

The ```user_error_information``` just returns an an i18n key for internationalization.  The user experience is up to the consumer, and higher up in the application.  Returning an internationalization key explicitly tells the reader that we are returning something for the user to see, and protects information leaks.

Error configurations can be injected for custom i18n keys to be returned, when the consumer has specific instructions depending on the error.

This is messy, but I just try to find a pattern in the backtrace as a link to an eid.  It will be hard to maintain in the future, but works for now.

There are no guards, throws or raises in the business logic, and looks like the first day when we only cared about the happy path:

```ruby
require 'active_support/core_ext/time/calculations.rb'                                                   
require 'httparty'
require 'time'

module Rescuetime
  class Fetch
    def self.call(datetime)
      formatted_date = format_date(datetime)
    
      response = request(formatted_date)
    
      response.fetch('rows').map do |row|
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

    def self.format_date(datetime)
      Time.parse(datetime).strftime('%Y-%m-%d')
    end
                                                  
    def self.request(datetime)              
      url =                                 
        "#{ENV['RESCUETIME_API_URL']}?"\    
        "key=#{ENV['RESCUETIME_API_KEY']}&"\
        "restrict_begin=#{datetime}&"\        
        "restrict_end=#{datetime}&"\          
        'perspective=interval&'\              
        'resolution_time=minute&'\          
        'format=json'

      HTTParty.get(url)
    end
  end
end                                         
```
[ex3 and tests](http://github.com)

The only difference is I broke out a format_date method so that identifying what the real error was would be easier.  Right now I'm finding out what happend by matching a pattern to the backtrace, and that is easier to do if I encapsulate potential failures with methods of their own.

What's needed most now is a way to simplify our error identification and response.

### How to Handle Failure: Redux

#### Javascript

##### Callbacks Per Request

Javascript often makes asynchronous calls.  Programming for asynchronous systems makes error handling more difficult -- asynchronous execution makes it impossible to program error handling like a blocking language.

As a simple example, let's look at a common ajax request:

```javascript
$.ajax({
  url: 'https://my-api.com/results.json',
  success: successHandler, // defined elsewhere
  error: errorHandler
});

console.log('Request sent!')
```

The error handler being scoped to this one function means that it knows exactly what use cases it should handle.  There doesn't have to be any grepping or data manipulation to figure out why an error occurs -- we will write an error handler for one specific request and no others.

While Ajax is probably the most well-known example of asynchronous Javascript, Reactive Javascript with RxJS has a significantly higher rate of asynchronous execution, and handles errors in a similar way with an error callback defined at the end of execution:

```javascript
const subscription = source
  .filter(quote => quote.price > 30)
  .map(quote => quote.price)
  .subscribe(
    price => console.log(`Prices higher than $30: ${price}`),
    error => console.log(`Something went wrong: ${error.message}`);
  );
```
[src](https://github.com/Reactive-Extensions/RxJS)

The functional collection pipeline breaks functions down into a granular level, and an error handler is set just off of the execution of those few functions.

### Lessons

##### Injectable Error Handling

Error handlers can be simpler when injected based on a method, or tightly knit group of methods.  Ajax does it for a single request.

The benefit of both injection and granularity means that the error handler is already scoped to a small set of potential responses.  Instead of a global handler that has to be prepared for any error the system throws, writing an error handler for a single function is significantly easier -- and understandable.

### Applying The Lessons: Redux

The first thing I did was break my methods down to the size where there could only be "one" reasons to fail.  If the reasons to fail were orthogonal to one another, they went into separate methods.  Then I pipelined them together in typical Ruby method-chaining.  Like Javascript, my hope was to have method-level identification in the injected error handler: 

```ruby
require 'boundary'
require 'rescuetime/pipeline'
require 'rescuetime/error_handler'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error =
      Rescuetime::Pipeline.new(datetime)
        .format_date
        .build_url
        .request
        .fetch_rows
        .parse_rows
        .on_error(Rescuetime::ErrorHandler.new)
  end
end
```

Let's take a look at the pipeline:

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'
require 'boundary'

module Rescuetime
  class Pipeline
    extend Boundary

    def format_date(time)
      Time.parse(time).strftime('%Y-%m-%d')
    end

    def build_url(date)
      "#{ENV.fetch('RESCUETIME_API_URL')}?"\
      "key=#{ENV.fetch('RESCUETIME_API_KEY')}&"\
      "restrict_begin=#{date}&"\
      "restrict_end=#{date}&"\
      'perspective=interval&'\
      'resolution_time=minute&'\
      'format=json'
    end

    def request(url)
      HTTParty.get(url)
    end

    def fetch_rows(response)
      response.fetch('rows')
    end

    def parse_rows(rows)
      timezone = ENV.fetch('RESCUETIME_TIMEZONE')
      rows.map do |row|
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

    protect!
  end
end
```

Extend then protect.  It'd be nice to remove the protect! call from the bottom, but I haven't decided on an API I like yet.

The ```Boundary``` looks a little crazier, especially with the metaprogramming:

```ruby
module Boundary
  def protect!
    methods = instance_methods - Object.instance_methods

    define_method("initialize") do |value|
      @result = value
    end

    define_method("on_error") do |handler|
      err =
        if @method && handler.respond_to?(@method)
          handler.__send__(@method, @result, @error)
        elsif @method
          handler.__send__(:default, @result, @error)
        end

      [@result, err]
    end

    methods.each do |method|
      define_method("protected_#{method}") do
        return self if @failed

        begin
          @result = __send__("original_#{method}", @result)
        rescue => e
          @failed = true
          @error = e
          @method = method
        end

        self
      end

      alias_method "original_#{method}", method
      alias_method method, "protected_#{method}"
    end
  end
end
```

The ```ErrorHandler``` is interesting -- define the name of the method you will handle the error for, and have it take the data and the error:

```ruby
require 'error'

module Rescuetime
  class ErrorHandler
    def format_date(data, error)
      Error.new(error, :invalid_date).log
    end

    def fetch_rows(data, error)
      if data[:error] == "# key not found"
        Error.new(error, :invalid_api_key).log
      else
        default(data, error)
      end
    end

    def default(data, error)
      Error.new(error, :default).log
    end
  end
end
```

This is explicit, simple, and easily changable -- it reminds me a bit of pattern matching.  No more detailed filters and matches in backtraces.  It also allowed me to delete the old, more complicated ```ErrorHandler```.

There is also a default method that gets called if there is no error handler setup for the method.  I also decided to return the Error itself instead of just a symbol.  This makes things a bit less strict, but I like the flexibility.

The ```Error``` is similar, though everything is private but the i18n key for the front end to use:

```ruby
require 'logger'
require 'pretty_backtrace'
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

class Error
  attr_reader :i18n

  def initialize(error, i18n)
    @error = error
    @i18n = i18n
  end

  def log
    Logger.error(system_error_information)
    self
  end

  private

  def system_error_information
    {
      error: @error.inspect,
      backtrace: @error.backtrace[0...5],
      i18n: @i18n
    }
  end

  def user_error_information
    @i18n
  end
end
```

If something changes and we want some more information for the front end to use, we'd only have to change the error object.

[ex4 and tests](http://github.com)

### Wrapping Up

The abstractions we made above are still evolving, though we do see that we have a single place to handle errors.  It's maintainable, explicit, and allows greater ability to adapt to the more exotic failures we will encounter as we scale.

Depending on the convention set in your own system and the language itself, there could be many interpretations of the following principles:

##### Encapsulate and Scope Error Handling

Scope to small enough scope in your application to where an error handler can identify and respond to failure without overwhelming complexity.

A good abstraction in handling failure can simplify an application's architecture, and allow an organization to respond to failure better as they scale.

If we'd like to introduce circuit breakers, semaphores, rate limiters or some sort of sharding abstractions, we have a boundary area in order to know where it will live.  This area can also be explored as a place to introduce failure for GameDay exercises and fault injection testing.

##### Decide on what an error needs to communicate

Above I returned an i18n key and sent in a custom JSON structure for the system to consume.  There is a lot more here to delve into, and most of it is custom to your organizational needs.

Whatever you decide your system/developers and the consumers must see, make sure it makes sense and aids them in accomplishing their goals.

##### Prefer injectable error handlers

This makes the error handling abstraction more generic and extensible.  The explicit nature of seeing what error handler handles what series of behavior also limits scope and simplifies where changes need to happen.

### When it breaks down

- Collection Pipelines, or method chaining may not fit nicely into your application.  Some existing designs may not have a nice way to identify failure implicitly.  If you are working in a system that already has failure being handled multiple ways in numerous locations, a different convention might have to be implemented to start encapsulating that error handling without a huge facelift on system design.

- What if I want a more sophisticated response instead of just logging and returning?  Some applications may want to retry on certain parts of their logical flow rather than failing outright.  Some may want to use a null object or guard in a limited scope, or even do some basic data validations inline.

- complacency during failure

> If you think you can prevent failure, then you aren’t developing your ability to respond.

[src](http://www.kitchensoap.com/2010/11/07/mttr-mtbf-for-most-types-of-f/)

since most errors are caught, you as an organization may expect all errors to be handled gracefully.  Keep in mind that your system, no matter how comprehensive the error handling, will still crash and fail unexpectedly. 

Don't let good error handling silence discussion and practice around your organization's ability to respond to catastrophic failure.  Continue to introduce failure through fault injection and GameDay exercises.

From above:

While fault tolerance is something normally only large companies are thought to be concerned with, small companies need to think about it too, to allow your company to change more easily to face the different needs that failures present.

Fault tolerance is normally something only large applications need to be concerned about.  Many large applications wouldn't survive without good approaches to fault tolerance.  For many small applications, fault tolerance is an afterthought, and something peppered in along the way.  Handling failure is not seen as a business necessity.

This is correct.  Small applications will not see the same exotic and business crippiling failures that large applications do at scale.  But for a small application there could only be a handful of users, and the worst we could see are stack traces.  Defer fault tolerance and defer handling errors.

But here is what small applications overlook and the hypothesis I will prove in this essay: thinking about fault tolerance early and making it a core philosophy in the system design, handling more levels of fault tolerance as you scale becomes much simpler and cheaper.  Not only that, but it brings transparency to your team's organizational response to failure, and allows the business to better plan to increase your ability to deal with different types of failure at different stages of your company's growth.

The sophistication of how your application responds in the face of failure is unique to your company's needs.  A large company will have a much different set of requirements than a company that serves 10 users.  Setting up multi-region redundancy would probably kill a small company from costs.  A company like Groupon would probably be killed if it didn't have a mature fault tolerant infrastructure setup.

The beauty of what we have above is that it allows us to defer the most expensive parts, and reduces complexity and cost of including them when the time comes to introduce them.

##### Defer the complexities of some failure states without ignoring them

At the most fundamental level, this design allows us to control how the application behaves in the face of all circumstances but the failure of the server this code runs on itself.

We could become much more sophisticated in alerting the user to which services are still available, or what happens after some failure states.  But fundamentally, all errors are controlled in a uniform way.

Even in a small application, the way we respond to certain failures can become complex and expensive.  But because we already handle the error in a fundamentally sound way, we can defer it, and when we want to address it, we already have a cleanly abstracted place to make the change.

Your system must still respond in the face of failure to be considered fault tolerant.  How it responds is where the art comes in.  What is certain is that how your system responds is as much subject to change as any business requirement and must therefore be architected with the same care in terms of making it easy to change.

##### defer more mature stability patterns

Circuit breakers, rate limiters/controlling backpressure, timeouts and semaphores are a few software abstractions to aid stability and fault tolerance.  Because we've already set clear abstractions for error handlinng, we know exactly where most of this stuff will go.

##### Future software changes for failure response are cheaper

instead of large refactorings, we are in a place to easily include and share these patterns

##### Promotes a more mature way to think about failure for a business


Good engineering can respond to unexpected failure.  It's up to you to determine what type of failure you will respond to.

Safety comes from adaptive capacity: http://www.kitchensoap.com/2011/04/07/resilience-engineering-part-i/ (recovering from failure quickly is more important than having less failures overall)  Your company considers, and has abstractions in the software for how to deal with responses more maturely, and promotes a more software-centric approach to stability.

##### Defer hardware redundacy

We are not truly fault tolerant until we address hardware failure.  For a small company, not having redundancy at the hardware level may be an appropriate cost.  The scale may not require it.

By making a few smart design decisions early on in a project, we can handle failure in an elegant, controlled manner.  Failure at scale becomes more manageable, and these principles can apply to any language.

#### Sources

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

https://blog.golang.org/errors-are-values




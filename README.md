## Exploring Levels of Fault Tolerance

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

### Design Considerations for Handling Failure

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

    def eid
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

I like where this is headed -- there is a single, localized place to handle error, the happy path is clear and void of failure logic, and we have a place to add and refactor for failure cases.

There is still a big pain point: I'm finding out what happend by matching a pattern to the backtrace.  While this may be ok for now, it's a bit cumbersome to understand, and I think we'll have big problems with it the larger the system gets.

### Design Principles for Easier Failure Identification

#### Collection Pipelining

A collection pipeline is a pattern where the output of one function is the input into the next function.  Functions can then be chained together in a highly readable, functional way.

It is a prevelent and powerful programming paradigm -- this may look familiar:

```bash
cat items.txt | sort | uniq | less | grep "find me?"
```

Here is an example of Javascript as a collection pipeline using the [RxJS](https://github.com/Reactive-Extensions/RxJS) library, a library for functional reactive programming:

```javascript
const subscription = getAsyncStockData()
  .filter(quote => quote.price > 30)
  .map(quote => quote.price)
  .subscribe(
    price => console.log(`Prices higher than $30: ${price}`),
    err => console.log(`Something went wrong: ${err.message}`); // error handler
  );
```
[src](https://github.com/Reactive-Extensions/RxJS)

This looks a lot like Ruby's method chaining!  But let's look a bit closer: every action in the sequence is small and they do one thing only, and there is a single error handler for the entire chain of execution.

This sort of design could work -- it looks like conventional ruby, and we can scope error handling to a single statement in the flow.  But how can we implement this?

#### Aspect-Oriented Programming
[Aspect-Oriented Programming](https://en.wikipedia.org/wiki/Aspect-oriented_programming) is a programming paradigm that adds behavior to existing code without modifying the original structure of that code.  An "advice" in AOP is a function that modifies the behavior of another function when it is run.

AOP is designed to allow a program to add concerns that are not vital to business logic to be added without polluting the business logic.  This is exactly what we have been trying to do the whole time!  Keep the happy path clear, but don't forget about the other core utilities the application needs to run.

Most languages need some extra tooling to make this happen.  But in Ruby, we have metaprogramming.

### Time To Refactor: Playing to Ruby's Strengths

Metaprogramming makes AOP easy to implement -- no extra libraries or frameworks needed and method chaining as a collection pipeline is a conventional pattern.  Let's take another crack at the code:

```ruby
require 'boundary'
require 'error_handler'
require 'rescuetime/pipeline'

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
        .final
  end
end
```

This cleaned up very nicely, I really like it.  Let's take a look at the pipeline:

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'
require 'boundary'

module Rescuetime
  class Pipeline
    extend Boundary

    def initialize(time)
      @result = time
    end

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

    protect! [
      { method_name: :format_date, i18n: :invalid_date},
      { method_name: :fetch_rows, i18n: :invalid_api_key, extra: lambda { |data, error|  data[:error] == "# key not found" } }
    ]
  end
end
```

Protect at the bottom, and the initial value getting set to a result instance variable.  Need to call ```final```.  

The ```Boundary``` looks a little crazier, especially with the metaprogramming:

```ruby
require 'error_handler'
require 'logger'

module Boundary
  def protect!(on_error_config = [])
    methods = instance_methods - Object.instance_methods
    error_handler = ErrorHandler.new(on_error_config)

    define_method("final") do |*args, &block|
      return @final_value
    end

    methods.each do |method|
      define_method("protected_#{method}") do
        return self if @failed

        begin
          @result = __send__("original_#{method}", @result)
          @final_value = [@result, nil]
        rescue => e
          @failed = true
          error = error_handler.error_for(e, method, @result)
          Logger.error(error.system_error_information)

          @final_value = [nil, error.user_error_information]
        end

        self
      end

      alias_method "original_#{method}", method
      alias_method method, "protected_#{method}"
    end
  end
end
```

The ```ErrorHandler```:

```ruby
require 'error'

class ErrorHandler
  DEFAULT_CONFIG = { i18n: :default }

  def initialize(config)
    @config = config
  end

  def error_for(e, method, result)
    i18n = i18n_for(e, method, result)
    Error.new(e, i18n)
  end

  private

  def i18n_for(e, method, result)
    extra_config = extra_for(e, method, result)

    if extra_config
      return extra_config[:i18n]
    else
      default_for(method)
    end
  end

  def extra_for(e, method, result)
    extras = @config.select do |c|
      c[:method_name] == method && c[:extra]
    end

    if extras
      extras.find do |c|
        c[:extra].call(result, e)
      end
    end
  end

  def default_for(method)
    @config.find(lambda { DEFAULT_CONFIG }) do |c|
      c[:method_name] == method && !c[:extra]
    end[:i18n]
  end
end
```

The ```Error``` is unchanged:

```ruby
require 'pretty_backtrace'
PrettyBacktrace.enable
PrettyBacktrace.multi_line = true

class Error
  attr_reader :error

  def initialize(error, i18n)
    @error = error
    @i18n = i18n
  end

  def system_error_information
    { error: @error.inspect, backtrace: error.backtrace[0...5], i18n: @i18n }
  end

  def user_error_information
    @i18n
  end
end
```
[ex4 and tests](http://github.com)

If we start operating as a collection pipeline full of single responsibility actions, our error handling code is simplified since there is usually only one reason each one of these methods could fail.

### Fault Tolerance At Scale

Now we enter the part that most people consider fault tolerance.  "Simply catching errors isn't fault tolerance!  Where is the hardware redundancy and hot backups!" they may say.  For most people, fault tolerance is coupled to scale.

While it is true that total fault tolerance must handle hardware failure, we wouldn't be fault tolerant without the foundation we've set, and in many ways, while scale breeds more exotic reasons to fail, fault tolerance is orthogonal to scale.  And for small applications, it is OK to defer more expensive stability measures until operating at scale.

Circuit breakers, rate limiters/controlling backpressure, timeouts and semaphores are a few software abstractions to aid stability and fault tolerance.  Because we've already set clear abstractions for error handlinng, we know exactly where most of this stuff will go.  

Let's add a circuit breaker and a timeout for the HTTP request:

ex4 -- show circuit breakers and timeouts; and more complicated failure responses

This is the place where failure is a chance to add value.

Defer the expensive parts: instead of large refactorings and rewrites, we are in a place to easily include and share these patterns.

##### Moving to Smarter Error Response

http://githubengineering.com/exception-monitoring-and-response/

### Conclusion

By making a few smart design decisions early on in a project, we can handle failure in an elegant, controlled manner.  Failure at scale becomes more manageable, and these principles can apply to any language.

#### Sources

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

https://blog.golang.org/errors-are-values




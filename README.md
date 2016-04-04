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
*[ex1 and tests](http://github.com)*

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
      formatted_date = DateTime.parse(datetime).strftime('%Y-%m-%d')
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

What we've done is a very natural progression in most projects: get the happy path out the door, setup exception notification, and fix the errors as they come in.  It seems reasonable, but let's look at some patterns in the code and progression:

1. Failure becomes more complex as the system grows
2. If 1 is true, then failures are less complex in smaller systems
3. Handling failure adds complexity and cost to the system
4. If 1 and 3 are true, then the larger the system gets, the more complex and costly failure handling will become
5. The system will still be used by customers even if it is experiencing partial or total failure.
6. If 5 is true, then the product should be expected to satisfy a set of use cases during failure.

We can see these patterns hold: there is nearly the same amount of error handling code as we do happy path code, and we are only handling a fraction of all possible errors.  Our module's post-conditions are complex:  sometimes we return nil, an object that has a message for the user or the real value. Sometimes we use begin/rescue for flow control.  Sometimes we use conditionals -- and this is only the first round of fixes based on failure.

The error handling we did put in place, though, allows graceful degredation of certain features, allowing the user to properly use the application in some capacity.  The negative to this, though, is that by capturing errors and not re-raising them, we lose the transparency and metrics exception notification provides.

### How To Handle Failure

Unless we stop and consider some basic error handling abstractions, more modules will be added to the system and are doomed to repeat the above process.  The larger the system gets, the more we will be unable to safely and clearly apply many levels of fault tolerance.  What we need is to learn about how to handle failure a more mature way. 

> While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.

http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/

#### Go

> Any function that does I/O, for example, must confront the possiblity of error, and only a naive programmer believes a simple read or write cannot fail.  Indeed, it's when the most reliable operations fail unexpectedly that we most need to know why.

> Alan A. A. Donovan and Brian W. Kernighan

http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS

##### Explicit Errors

In Go, ```error``` is built-in, ordinary value.  The creators of Go saw that exceptions add complexity.  Throws, rescues, catches and raises pollute the control flow.  For Go, errors are a natural part of a healthy program running in production and should be consciously handled.

Instead of blocks that scope code execution for protection -- like a begin/rescue in Ruby -- Go uses normal control flow mechanisms like if and return to process errors:

```go
f, err := os.Open("filename.ext")
if err != nil {
    log.Fatal(err)
}
```

http://blog.golang.org/error-handling-and-go

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

http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG

Erlang is known as a language to build highly scalable, fault tolerant systems of a massively distributed nature.  Let's explore why Erlang is so good at dealing with failure.

##### Process Isolation

A large part of Erlang's ability to keep operating despite failure is process isolation.  A process in Erlang is responsible for doing a discrete unit of work in total isolation -- no memory sharing, no locks and no dependent communication with other processes.

Erlang/OTP applications are usually represented as a tree structure, where one process, known as a supervisor, will oversee the worker processes.

The supervisor is responsible for observing and orchestrating the workers, which should do the bulk of the business processing.  When a process encounters an issue, Erlang's philosophy is to let it crash, or fail fast. Erlang/OTP systems _expect_ error to occur and build handling into the supervisor.

Coming from a defensive programming mindset, this may seem outright dangerous.  But Erlang believes failing processes quickly helps avoid data corruption and transient bugs that commonly cause system crashes at scale, and forces confronting error earlier rather than later.

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
http://erlang.org/doc/reference_manual/processes.html

Among other things, the monitor will receive a down signal with a reason and the pid that went down.

A supervisor will usually use links and monitors with spawned child worker processes, and depending on the message and reason, will know what to do in case of failure, such as restarting the process.

Keeping error handling in the supervisor encapsulates logic around failure, and reduces the complexity error handling adds to other parts of the application.

### Design Considerations for Handling Failure

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/

##### Errors for the System, and Errors for the User

Two segments will see error: the system and engineers, and the public.  Make sure whatever is seen is appropriate.

For the public, they should not see stack traces.  They should be given a good error message and information on what they can do in the meantime.

For the system and engineers, make sure data is structured in a way that makes diagnosis and problem analysis easy.  Go gives a causal string for high-level understanding and Erlang gives a list of tuples as a strack trace for programatic analysis.

For either party, the goal is a simple user experience.

##### Error Handling Changes System Convention

> You can try to prevent bugs all you want, but most of the time, some will still creep in.  And even if by some miracle your code doesn't have any bugs, nothing can stop the eventual hardware failure.  Therefore, the idea is to find good ways to handle errors and problems, rather than trying to prevent them all.
> 
> Fred Hebert

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

http://blog.golang.org/error-handling-and-go

Let's rewrite our Rescuetime code with these principles:




##### Causal Errors for the Consumer and the Engineer

I added pretty backtrace and limited the backtrace by eliminating the ruby gem files from it.  Pretty backtrace also provides variables for better diagnosis of the issue at hand.  I log as well.

The consumer receives an ```eid``` or error identifier.  The presentation of that error is up to the consumer, not the module.

##### Fail Fast in One Way

I treat everything like a crash -- I don't control it.  This is nice because now even errors I don't expect will be treated like errors I do expect.

##### Localized, Single Handler

Done at the module boundary level, and can be fully documented.  This is already how Go's convention is for error documentation.

### More Levels of Fault Tolerance

The user sees no stack traces.  All errors are handled.  The system knows about every error that is handled.  The user always sees some sort of graceful error message.  Now we've grown to a point where we are seeing some more exotic errors.

There is a lot to application stability than simply rescuing errors.  There are circuit breakers, rate limiters, timeouts, semaphores and hardware sharding.  This is where stuff gets more expensive and difficult to change, but for us, we know exactly where it goes.  Let's add a circuit breaker and a timeout for the HTTP request:


ex4 -- show circuit breakers and timeouts

This is the place where failure is a chance to add value.

- Defer the expensive parts: Testing for change of business logic seems to be widely accepted, but anticipating change for failure or scale is not because it is seen as too complex, or expensive.  Point: have a design that can anticipate those problems, and defer the expensive parts until you need them.

There is so much more to do for a fault-tolerant, scalable distributed system -- circuit breakers, rate limiting, request tracing, sharding -- implementing all of them would probably cost too much for most applications starting out.  But with the boundary in place, it is obvious where all of that should be included in the application.  Instead of large refactorings and rewrites, we are in a place to easily include and share these patterns.


##### Error has been simplified

Before, how we handled error, and all the use cases weren't documented and seemed insurmountable.  Now, failure cases are explicit and can be put in the sights of the business to define use cases around partially or fully degraded service.

##### How this relates to Reactive Programming

"Reactive Programming raises the level of abstraction of your code so you can focus on the interdependence of events that define the business logic, rather than having to constantly fiddle with a large amount of implementation details." https://gist.github.com/staltz/868e7e9bc2a7b8c1f754

Maybe get into collection pipelines with logging?  How the structure of your application makes it easier to do, like reactive functional programming.

##### Moving to Smarter Error Response

http://githubengineering.com/exception-monitoring-and-response/

#### Sources

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/




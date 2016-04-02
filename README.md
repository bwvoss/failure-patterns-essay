## Exploring Levels of Fault Tolerance

To start, I'm going to lay out some assumptions that I do not have empirical proof for, but I think are mostly correct:

#### The 6 Assumptions of Failure in Software

1. Failure becomes more complex as the system grows
2. If 1 is true, then failures are less complex in smaller systems
3. Handling failure adds complexity and cost to the system
4. If 1 and 3 are true, then the larger the system gets, the more complex and costly failure handling will become
5. The system will still be used by customers even if it is experiencing partial or total failure.
6. If 5 is true, then the product should be expected to satisfy a set of use cases during failure.

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

This is nice enough. Depending on coding style we may extract some methods, but we just intuitively like it and all think it's easy enough to work with. The business logic is clear. The tests clearly describe the behavior.

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

At this point, alarms should be going off in our head, but it's really not that painful yet.  What we've done is a very natural progression in most projects: get the happy path out the door, setup exception notification, and fix the errors as they come in.  By the time we realize the missing encapsulations, it'll probably be too late for an affordable refactor.

We have nearly the same amount of error handling code as we do happy path code, and we are only handling a fraction of all possible errors.

Our module's post-conditions are fairly complex.  Sometimes we return nil.  Sometimes we return an object that has a message for the user.  Sometimes we use begin/rescue for flow control.  Sometimes we use conditionals.  Luckily we are consistent that if something is wrong, we stop the flow of execution, but that is not enforced and will easily be changed depending on what the next error is we have to fix (like if the response has no 'rows' key, we may default that fetch to an empty array).

While our users aren't seeing stack traces spewed onto their screens, we loose transparency and metrics.  One benefit of an exception notifier is the transparency it provides on how our system operates.  Swallowing errors or using guards doesn't fix the system, they just make the error notifier stop notifying.  The team's understanding of the system is inconsistent with reality.

We keep adding features, and as exceptions pop-up, we keep fixing them.  Meanwhile, lacking an abstraction to deal with error means the other features being built will repeat this process.

### A checkin with the assumptions

Still true to the assumptions of failure in software, the error handling has increased the complexity of our code and as our codebase grows, the complexity of the error and how we handle them increase.

The error handling we did put in place, though, gracefully degraded features, while allowing the user to explore other parts of the system.  We haven't really explored the opportunity that handling failure can provide, but the product can still satisfy a set of use cases during partial failure.

According to our principles, the codebase is growing, so the cost of handling error will continue to increase, and so will the complexity of our code.  What we need is a way to keep the cost and complexity of handing failure rise exponentially as more errors are fixed, or as the system grows.

### How To Handle Failure

> While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.

http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/

#### Go

> Any function that does I/O, for example, must confront the possiblity of error, and only a naive programmer believes a simple read or write cannot fail.  Indeed, it's when the most reliable operations fail unexpectedly that we most need to know why.

> Alan A. A. Donovan and Brian W. Kernighan

http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS

##### Explicit Errors

In Go, ```error``` is built-in, ordinary value.  The creators of Go saw that exceptions, and the tooling required to handle them, add complexity.  Understanding the control flow becomes more difficult and the developer has more chances to make mistakes.  For Go, errors are a natural part of a healthy program running in production and should be consciously handled.

Instead of blocks that scope code execution for protection, Go responds to errors using normal control-flow mechanisms like if and return:

```go
f, err := os.Open("filename.ext")
if err != nil {
    log.Fatal(err)
}
```

http://blog.golang.org/error-handling-and-go

Explicitly checking for errors demands error handling logic receives attention.  Coupled with Go's static typing, errors need to be explicitly ignored.

This is refreshingly different from most languages where exceptions are easily ignored and the user subsequently sees incomprehensible stack traces.  Go forces the developer to face errors a natural running system could produce.

Go has something called ```panic``` as well, which is like an exception in other languages.  Conventionally, a panic is used when when the system is totally broken and in an unrecoverable format.

##### Communicating With Error messages

Errors are a communication tool for humans to know what went wrong.  The Go community establishes a convention for error messages that make it easy for operators to track down what went wrong in a casual chain with strings.  Let's say we wanted to craft an error message for an HTTP timeout failure for the Rescuetime code.  In Go, it may be structured like this:

```go
rescuetime: fetch: http timeout: the url of http://rescuetime-api.com timed out at 5 seconds
```

A chain of strings is an easy data structure to scan or grep, and gives a uni-directional view leading to the failure.

#### Erlang

> The best example of Erlang's robustness is the often-reported nine nines (99.9999999 percent) of availability offered on the Ericsson AXD 301 ATM switches, which consist of more than a million lines of Erlang code.
> 
> Fred Hebert

http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG

##### Process Isolation

Erlang is designed to have millions of independent processes running in isolation.  A failure in one of the components shouldn't impact the rest of the system's ability to work.  Erlang systems _expect_ error.

Letting a process crash -- or fail fast -- is central to error handling in Erlang.  When there is a problem, do not return default values or null objects, and don't swallow the error.  Just crash.

Coming from a defensive programming mindset, this may seem outright dangerous.  But Erlang believes failing processes quickly helps avoid data corruption and transient bugs that commonly cause system crashes at scale.

Failing fast also gets the application used to failure.  Defensive programming gives the product an illusion of fault tolerance. Remember -- to Erlang, error is inevitable.  Even if the application code handled every possible error, failure can still occur from an underlying hardware, security or network problem.  Letting processes crash makes the application consider error handling from the beginning.

##### Supervisors, Links and Monitors

A Link is a bidirectional bond between two processes.  When a process crashes, the linked processes will also terminate or handle the exit in some way.  A process can trap the exit from a linked process to prevent its own termination and can handle the resulting exit signal, that looks like this:

```erlang
{'EXIT', FromPid, Reason}
```
If observation is all that is needed, Erlang provides Monitors.  A process can have multiple monitors attached to it.  Erlang allows us to monitor a process like this:

```erlang
erlang:monitor(process, MonitoredPid)
```

When the monitored process terminates, the monitor will receive this data structure:

```erlang
{'DOWN', Ref, process, MonitoredPid, Reason}
```

http://erlang.org/doc/reference_manual/processes.html

A supervisor is a process that monitors and can restart other processes (even other supervisors!).  When the supervior dies, all child processes should also die (using a link), but when a child process dies, the supervisor should recognize the failure, and decide whether to restart the process or not (using a monitor).

Supervision is useful in a lot of ways.  Supervising processes ensures that they are cleaned up properly.  Spawing thousands and thousands of processes without managing them could easily result in memory starvation.  Supervisors also provide the order of how the application behaves at a high level, and the place where error handling can easily be confined.

The supervisor to worker relationship is well-defined and often described using tree-like graphs.  Supervisors collect data from, and control workers.  Workers do the business logic and don't worry about error handling.

About a year ago, Michael Feathers introduced me to a concept called "the chocolate shell and the creamy center". The concept has two points: first, that error handling and logging are separate responsibilities from business logic.  It should be encapsulated and abstracted in what he called "the chocolate shell".  Second, the rest of the code should just assume data is going to be in a good state to be used -- "the creamy center".  This is exactly what Erlang attempts with supervisors and workers.

This approach to failure handling reduces the complexity error handling adds to sections of business logic.  It also provides a simple convention on where and how to handle failure.

#### Lessons From Go and Erlang

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/

##### Make Error Handling a Foundational Abstraction

> You can try to prevent bugs all you want, but most of the time, some will still creep in.  And even if by some miracle your code doesn't have any bugs, nothing can stop the eventual hardware failure.  Therefore, the idea is to find good ways to handle errors and problems, rather than trying to prevent them all.
> 
> Fred Hebert

Errors will *ALWAYS* happen.  Make error handling central to a system's design.  Basic fault tolerance should not be added in as an afterthought.  Consider the positive implications that having error as an explicit type provides: programmers are forced to confront the possiblity of failure on their very first I/O call.

##### Fail Fast In One Way

Go doesn't have throw/catches or (raise|fail)/rescues: an error is an error.  If it prevents the system from working correctly on the happy path, be like Erlang and jump out to handle it.  The handler needs to only concern itself with what to do in case of failure.

The user should see a graceful response no matter what.  The method an error was propogated up is invisible to them -- so long as it is handled.  All of these different ways of signaling an error has happened is for developer communication, and the variance is what is damaging.

As stated above, errors will happen that we can't anticipate, so ensuring problems get filtered through the same location make us a bit safer when facing unrealized problems.

By simplifying the way we signal we have an error, and failing fast from it, we simplify the code, and reduce the chance of propogating stability cracks or data inaccuracies.

##### Localize and Scope Error Handling

With only one way to signal a problem, the handler has to be scoped enough to the flow of logic to still keep it simple.  In Erlang, a supervisor will handle failure for its worker processes, but only its own.  Localized and uniform error handling simplifies flow control.  Business logic can also be void of error handling and can be solely written to communicate and acheive business goals.

Without strategic, localized points to handle the failure, we would need to bubble the error up to another level and would likely add unwanted complexity.

##### Errors Are Communication Tools

We've also seen specific conventions for giving humans what they need to diagnose what the heck happened.  Errors should be used as reports for the system and engineers to understand problems.  The system should also send a different error specifically for the user experience.

### Applying the Lessons

> Proper error handling is an essential requirement of good software.
> 
> Andrew Gerrand

http://blog.golang.org/error-handling-and-go

Let's rewrite our Rescuetime code with these principles:










ex3

##### Causal Errors for the Consumer and the Engineer

I added pretty backtrace and limited the backtrace by eliminating the ruby gem files from it.  Pretty backtrace also provides variables for better diagnosis of the issue at hand.  I log as well.

The consumer receives an ```eid``` or error identifier.  The presentation of that error is up to the consumer, not the module.

##### Fail Fast in One Way

I treat everything like a crash -- I don't control it.  This is nice because now even errors I don't expect will be treated like errors I do expect.

##### Localized, Single Handler

Done at the module boundary level, and can be fully documented.  This is already how Go's convention is for error documentation.

##### More Levels of Fault Tolerance

Level 1: The user sees no stack traces.  All errors are handled.  The system knows about every error that is handled.  The user always sees some sort of graceful error message.

Level 2: Rate limiting, Circuit Breakers, Timeouts (probably with vertical scaling)

This is the place where failure is a chance to add value.

Level 3: Hardware fault tolerance (scale forces horizontal scaling and fault tolerance)

- Defer the expensive parts: Testing for change of business logic seems to be widely accepted, but anticipating change for failure or scale is not because it is seen as too complex, or expensive.  Point: have a design that can anticipate those problems, and defer the expensive parts until you need them.

There is so much more to do for a fault-tolerant, scalable distributed system -- circuit breakers, rate limiting, request tracing, sharding -- implementing all of them would probably cost too much for most applications starting out.  But with the boundary in place, it is obvious where all of that should be included in the application.  Instead of large refactorings and rewrites, we are in a place to easily include and share these patterns.

ex4 -- spike to show sharding and circuit breakers


##### Error has been simplified

Before, how we handled error, and all the use cases weren't documented and seemed insurmountable.  Now, failure cases are explicit and can be put in the sights of the business to define use cases around partially or fully degraded service.


#### Sources

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/




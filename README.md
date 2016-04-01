## Building For Fault Tolerance

TODO: Introduction

>
While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.

http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/

Let's assume a program that fetches and parses data from Rescuetime's API:

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime)
	response = request(datetime)

	parsed_rows = response.fetch('rows').map do |row|
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

This is nice enough. Depending on coding style we may extract some methods, but we just intuitively like it and all think it's easy enough to work with.  The Flog score is 21.2 -- pretty good.  The business logic is clear. The tests clearly describe the behavior.  We deem this acceptably clean code, and release the software.


> A brief note on Flog

> Flog is a Ruby gem that uses ABC (assignments, branching and conditionals) to measure complexity in a piece of code.  I don't use it an absolute judgement for complexity, but it is a nice supplement to personal heuristics.


More users have been complaining about seeing stack traces when using the app -- this is bad on a number of levels.  With more users, we are also getting more catastrophic failures.  We make a new release to handle as many failure cases as we can think of:

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'

class RescuetimeData
  def self.fetch(datetime, logger)
	begin
	  url = build_url(datetime)
	rescue => e
	  logger.fatal("Problem parsing url: #{e.inspect}")
	  return
	end

	begin
	  response = HTTParty.get(url)
	rescue => e
	  logger.fatal("Http failed: #{e.inspect}")
	  return
	end

	begin
	  parsed_rows = parse_response_to_rows(response)
	rescue => e
	  logger.fatal("Parsing date failed: #{e.inspect}")
	  return
	end

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
		date:				  ActiveSupport::TimeZone[timezone].parse(row[0]).utc.to_s,
		time_spent_in_seconds: row[1],
		number_of_people:	  row[2],
		activity:			  row[3],
		category:			  row[4],
		productivity:		  row[5]
	  }
	end
  end
end
```
*[ex2 and tests](http://github.com)*

Our code has become close to unreadable.  Our control flow is hard to follow.  We're using raises for everything, so it is possible we are swallowing errors we should handle differently.  If we add another rescue block on another level above, we are royally screwed in the "where did this error happen?" department.  The business logic is hidden behind a mass of log statements and rescue blocks.  While we have accomplished the business requirements, our code begs for a cleaning.  

This is progression is common in nearly every application I have seen with applications that add error handling when errors become an issue.  It's also common to see some modules do error handling at different levels, or a mix of error handling and sprinkled guard statements.  

The above example is small enough where refactoring it will not be an epic investment of time.  The larger the project gets without facing how to respond to failure, the more danger it assumes towards needing a massive rewrite later.  Failure, while maybe not as exotic as large projects, is still something small projects will face.

### How to Handle Failure

Some languages have already thought deeply about failure and how to deal with it from an early project state.  Others, like Ruby, make it easy to ignore failure until we becomed overwhelmed by faults.  Some languages don't make it that easy:

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

Letting a process crash is a central philosophy to Erlang.  Most systems will try to be error-free and defensively programmed.   Failing processes as fast as possible also helps avoid data corruption and transient bugs.  Even if by some heroic effort the application code handled every possible error, failure can still occur from an underlying hardware, security or network failure.

Erlang processes communicate through message passing and aren't required to receive an acknowledgement of reception, since a process could be sending a message to a process that currently doesn't exist, or will fail before the message can be processed.  As we will see, this provides a natural place to elegantly include error handling.

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

#### Principles in Failure

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/

##### Errors will *ALWAYS* Happen

> You can try to prevent bugs all you want, but most of the time, some will still creep in.  And even if by some miracle your code doesn't have any bugs, nothing can stop the eventual hardware failure.  Therefore, the idea is to find good ways to handle errors and problems, rather than trying to prevent them all.
> 
> Fred Hebert

##### Localizing Error Handling Makes Flow Control Simpler

Go makes errors explicit and allows us to use common flow control techniques to direct behavior in applications that experience failure. Erlang fails fast and monitors.  Superviors are used to capture and deal with failure leaving most processes to focus soley on business logic.

Business logic can also be void of error handling and can be solely written to communicate and acheive business goals.

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

##### Error Handling Must Be Considered Early

Central to app convention.  Expensive to add in later.

As an explicit type, errors have to be ignored on purpose.  Programmers are forced to confront the possiblity of failure on I/O calls.  Erlang designed around lightweight, independent workers that could die and be monitored separate from the business goal they are deployed to acheive.

In both languages, facing error is a central part of the design.  Fault tolerance is not added in as an afterthought.  
 
##### Handle Errors Generically

Both languages rarely deal with specific error handling.  Since exceptions or errors indicate a failure of some type, then the handler needs only make a decision on what to do in case of failure.  This is a much simpler approach.

We simplify what an error is by saying an error is anything that makes processing the application impossible. Ruby, as well as Erlang, want throws for expected errors and raises for unexpected errors.  Go shows us a simpler way: an error is an error.

Never have layered try-catches -- only one.  And it has to be at a level where we are in a position to know what to do about it. -- at the "process" or "actor" level

On top of that, this seems to relate to Go's recommendation of documenting the error cases, and is Design by Contract: https://en.wikipedia.org/wiki/Design_by_contract where pre and post conditions are declared explicitly.

##### Error Messages Are Communication Tools

We've also seen specific conventions for giving humans what they need to diagnose what the heck happened.  Having this convention baked in means creating context for human diagnosis is easy.

Let's rewrite our Rescuetime code with these principles:

ex3 -- the boundary example; annotate to the philosophies shown above

#### What comes next?

##### Adding more fault-tolerance

There is so much more to do for a fault-tolerant, scalable distributed system -- circuit breakers, rate limiting, request tracing, sharding -- implementing all of them would probably cost too much for most applications starting out.  But with the boundary in place, it is obvious where all of that should be included in the application.  Instead of large refactorings and rewrites, we are in a place to easily include and share these patterns.

ex4 -- spike to show sharding and circuit breakers

##### Homeostasis

Homeostasis is the property of a system to self-heal.

Erlang also expects autonomous recovery to a point -- software isn't really scalable if it fails often and requires human intervention every time.






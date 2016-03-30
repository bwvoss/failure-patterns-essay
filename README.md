## For Resiliency

TODO: Introduction

>
While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.
[^fail-quote]

[^fail-quote]: http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/

Let's assume a program that fetches and parses data from Rescuetime's API:

```
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

```
A brief note on Flog

Flog is a Ruby gem that uses ABC (assignments, branching and conditionals) to measure complexity in a piece of code.  I don't use it an absolute judgement for complexity, but it is a nice supplement to personal heuristics.
```

More users have been complaining about seeing stack traces when using the app -- this is bad on a number of levels.  With more users, we are also getting more catastrophic failures.  We make a new release to handle as many failure cases as we can think of:

```
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
>
"Any function that does I/O, for example, must confront the possiblity of error, and only a naive programmer believes a simple read or write cannot fail.  Indeed, it's when the most reliable operations fail unexpectedly that we most need to know why." -- Alan A. A. Donovan and Brian W. Kernighan
[^go-book]

[^go-book]: http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS

##### Explicit Errors

In Go, ```error``` is built-in, ordinary value.  The creators of Go saw that exceptions, and the tooling required to handle them, add complexity.  Understanding the control flow becomes more difficult and the developer has more chances to make mistakes.  For Go, errors are a natural part of a healthy program running in production and should be consciously handled.

Instead of blocks that scope code execution for protection, Go responds to errors using normal control-flow mechanisms like if and return:

```
f, err := os.Open("filename.ext")
if err != nil {
    log.Fatal(err)
}
```
[^go-source]

[^go-source]: http://blog.golang.org/error-handling-and-go

Explicitly checking for errors demands error handling logic receives attention.  Coupled with Go's static typing, errors need to be explicitly ignored.

This is refreshingly different from most languages where exceptions are easily ignored and the user subsequently sees incomprehensible stack traces.  Go forces the developer to face errors a natural running system could produce.

Go has something called ```panic``` as well, which is like an exception in other languages.  Conventionally, a panic is used when when the system is totally broken and in an unrecoverable format.

##### Communicating With Error messages

Errors are a communication tool for humans to know what went wrong.  The Go community establishes a convention for error messages that make it easy for operators to track down what went wrong in a casual chain with strings.  Let's say we wanted to craft an error message for an HTTP timeout failure for the Rescuetime code.  In Go, it may be structured like this:

```
rescuetime: fetch: http timeout: the url of http://rescuetime-api.com timed out at 5 seconds
```

A chain of strings is an easy data structure to scan or grep, and gives a uni-directional view leading to the failure.

#### Erlang

>“When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world >situation deviates from the specification” -- Joe Armstrong
[^joe-quote]

[^joe-quote]: http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/

##### Links and Monitors

Erlang is designed to be executed in a massively distributed nature.  Thousands, even millions of independent processes are going to be working in unison.  Being isolated, a failure of a process will not impact any other process (unless we want it to).


```
> erlang:monitor(process, Pid2)

% If the monitored process dies, the monitor will recieve:
{'DOWN', Ref, process, Pid2, Reason}
```
[^erl-process-example]

[^erl-process-example]: http://erlang.org/doc/reference_manual/processes.html

##### Supervision Trees

Erlang applications should be stable even if its worker processes crash all the time.




Isolated Processes and Message Passing (generic communication mechanism)

Erlang processes communicate through message passing and aren't required to receive an acknowledgement of reception, since a process could be sending a message to a process that currently doesn't exist, or will fail before the message can be processed.

loc 3170: "...taking the design approach of multiple processes with message passing was a good idea, because error handling could be grafted onto it relatively easily."

Fail Fast and Let it Crash (Don't catch exceptions! (mostly))

> "...errors are orthogonal to stability"
[^c2-orthogonal]

[^c2-orthogonal]: http://c2.com/cgi/wiki?LetItCrash

When a process encounters a problem, Erlang wants to let it crash.  According to Erlang, failure will always happen, no matter what, so application designers need to get comfortable handling errors:

"You can try to prevent bugs all you want, but most of the time, some will still creep in.  And even if by some miracle your code doesn't have any bugs, nothing can stop the eventual hardware failure.  Therefore, the idea is to find good ways to handle errors and problems, rather than trying to prevent them all."

Studies proved that one of the main sources of downtime in large-scale systems are intermittent or transient bugs.  When something is wrong in the application, fail fast to reduce the chance of data corruption and consuming resources that other processes may need.  

A system can terminate in two different ways: expected and unexpected (a crash).  Make sure all crashes are the same as clean shutdowns.

"...to kill processes as fast as possible to avoid data corruption and transient bugs."

What about hardware failures?  With "...independent processes with no communication channel outside message passing, you can have them all work the same way despite which node they operate on -- making fault tolerance through distribution nearly transparent to the programmer" loc: 3195

 
 loc3687: "...in order to be reliable, an application needs to be able to kill and restart processes quickly."


defensive programming vs. let it crash; this is important because your software will still crash even if you handle all the error states -- it's possible the underlying hardware or network will fail in some way.



https://mazenharake.wordpress.com/2009/09/14/let-it-crash-the-right-way/

questions to ask before happy path programming:
what errors to handle here specifically?  If not, then should I handle it?
when I crash the worker, should I restart?  What is cleanup looking like?

So we have to handle error, and handling error is complex and easily could triple or quadruple your lines of code.


Showing intent/indicating failure the right way:

The type of error thrown, while functionally the same, is used to show intent.  Is this error something that should kill the entire process, or something the user can handle?  In erlang, erlang:error returns a stack trace and kills the process, exit just stops code execution and returns.  

Throws in erlang, like ruby, are used when you expect the programmer to handle them, not to crash.  So it is common in erlang to throw when in deep recursion
 to a top level function which will handle it and return a { error, reason } tuple to the user.  Ruby will also use a throw/catch when the problem is expected and can be handled (a missing user input they can update), and raise/fail when the problem cannot be recovered from.  (though this seems confusing -- does it matter if you expect it or not?  The program cannot work without it.  Why not just have one...)

Returning defaulted (detailed) information on failure:

```
> catch 1/0

{{'EXIT', {badarith, [
  {erlang, '/', [1,0], []},
  {erl_eval, do_apply, 6, [{file, "erl_eval.erl"}, {line, 576}]},
   ...more tuples...] 
```
loc 2348
{Module, Function, Arguments}

#### What if this is software that manages a space shuttle?

Where do sensible defaults come into play?  What about data sanitation for security purposes?

Let's say we are building temperature regulation software for a spaceship.  Let's say that the inputs could really be anything -- we can't be sure only floats within a range will be entered.  Let's also say that due to the hardware and energy constraints on the ship, we can only change the temperature no more than once an hour.

We have a couple constraints -- the input must be a float between 55 - 80 degrees Farenheit and once an hour and if 66.6 is entered the hardware goes haywire.

_Dont drink the kool-aid_

Before I warned about using gaurd clauses with default data, or null objects with defaulted data.  Now I'm using them.  Could demonstrate the use of null objects or default data in a limited scope.

ex4 -- in golang 


#### Failure Meta Principles

Flow Control:

Go makes errors explicit and allows us to use common flow control techniques to direct behavior in applications that experience failure. Erlang fails fast and monitors.  Superviors are used to capture and deal with failure leaving most processes to focus soley on business logic.

> "With localized throws, flow control is simpler."
http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

Crashing vs. Null Object Data

Crashing means a piece of equipment stops operating.  This is something we consider bad, so we will write code to prevent crashes, like guard clauses or null objects.  

A potentially more indisdious side-effect of handling for crashes are problems of data integrity that could be caused by "intelligent" null objects or guard clause return values.  Plus, nil has to be handled somewhere so more code has to be written to handle the nils.

Error handling is central to how applications are built:

As an explicit type, errors have to be ignored on purpose.  Programmers are forced to confront the possiblity of failure on I/O calls.  Erlang designed around actors that could die and be supervised to protect system resources and the other responsibility of the system.

In both languages, facing error is a central part of the design.  Fault tolerance is not added in as an afterthought.  
 
Generic and scoped exception handlers:

Both languages rarely deal with specific error handling.  Since exceptions or errors indicate a failure of some type, then the handler needs only make a decision on what to do in case of failure.  This is probably for simplicity in the code.

We simplify what an error is by saying an error is anything that makes processing the application impossible. Ruby, as well as Erlang, want throws for expected errors and raises for unexpected errors.  Go shows us a simpler way: an error is an error.

Scoping the exception handling/Centralized Logic of handling error:

The global catch all puts you in a position to be most likely to make your own decision on what to do.  We don't want to be passively controlled by our program's failure cases.
 Never have layered try-catches -- only one.  And it has to be at a level where we are in a position to know what to do about it. -- at the "process" or "actor" level

On top of that, this seems to relate to Go's recommendation of documenting the error cases, and is Design by Contract: https://en.wikipedia.org/wiki/Design_by_contract where pre and post conditions are declared explicitly.

Error messages built for Humans:

Erlang and Go both have specific conventions for giving humans what they need to diagnose what the heck happened.  Having this convention baked in means creating the context of information is easy, and in data structures that aid humans in searching and filtering the data.

#### The Chocolate Shell and the Creamy Center

About a year ago, Michael Feathers introduced me to a concept called "the chocolate shell and the creamy center". The concept has two points: first, that error handling and logging are separate responsibilities from business logic.  It should be encapsulated and abstracted in what he called "the chocolate shell".  Second, the rest of the code should just assume data is going to be in a good state to be used -- "the creamy center".  As we've seen, other languages have this baked in, though I love the metaphor.

This approach to failure handling simplifies the business logic instead of being peppered with logs and rescues.  It also simplifies our failure logic by keeping all of the handling and recovery in a single place.

ex3 -- the boundary example; annotate to the philosophies shown above

#### What comes next?

##### Adding more fault-tolerance

There is so much more to do for a fault-tolerant, scalable distributed system -- circuit breakers, rate limiting, request tracing, sharding -- implementing all of them would probably cost too much for most applications starting out.  But with the boundary in place, it is obvious where all of that should be included in the application.  Instead of large refactorings and rewrites, we are in a place to easily include and share these patterns.

ex4 -- spike to show sharding and circuit breakers

##### Homeostasis

Homeostasis is the property of a system to self-heal.

Erlang also expects autonomous recovery to a point -- software isn't really scalable if it fails often and requires human intervention every time.






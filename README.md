## Application Patterns and Principles for Handling Failure

_Treating error handling as its own responsibility makes applications cleaner, and easier to change in case of failure.  In this blog, we look at the pitfalls of how error handling is traditionally approached, and by taking inspiration from languages like Go, Erlang, and JavaScript, we pattern a different encapsulation to handling failure that encourages simplicity._

### Table of Contents

The Usual Progression of Handling Error

Error Handling in:

Go

Erlang

Asynchronous Javascript

Failure Principles

The Principles Implemented

A Focus on Reducing Complexity

Sources

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

### Strategies in Error Handling

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

Erlang/OTP applications are usually represented as a tree structure, where one process, known as a supervisor, will oversee the worker processes.

The supervisor is responsible for observing and orchestrating the workers, which should do the bulk of the business processing.  When a process encounters an issue, Erlang's philosophy is to let it crash, or fail fast, and have a separate handler deal with the failure. Let's walk down this simple supervisor:

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

##### Process Isolation

A process in Erlang is a lightweight, isolated process in the Erlang VM. It is not a Kernel process.  A process in Erlang is responsible for doing a discrete unit of work in total isolation -- no memory sharing, no locks and no dependent communication with other processes.  One is invoked using the ```spawn``` built-in function in the start function:

```erlang
start(Mod,Args) ->
  spawn(?MODULE, init, [{Mod, Args}]).
```

```?MODULE``` is an Erlang macro that will evaluate to the name of the module at compile-time.  The second argument is the name of the function that will be invoked on the module, and the third argument is a list of arguments the function will receive.  In this case, ```sup```'s ```init``` function will be called with a tuple that has the values by-way of pattern matching with the arguments received.

The next method down looks similar:

```erlang
start_link(Mod,Args) ->
  spawn_link(?MODULE, init, [{Mod, Args}]).
```

The ```spawn_link``` built-in function also creates a new Erlang process that runs separate and asynchronously from our own process.  Besides creating a process, ```spawn_link``` atomically links our own process with the newly created one.  We will learn what a link is next, but this protects us from trying to link to a dead process.

##### Links and Exit Trapping

A link is a bidirectional bond between two processes.  If we are linked to a process and that process dies, we will also die.  This is a valuable tool when you have a supervisor looking after thousands of workers -- now if the supervisor dies, all linked processes will also be cleaned up.  But this could get us in trouble if a worker dies.  We want the supervisor to survive, and handle the problem.

The first line of the init function invokes a built-in function called ```process_flag```:

```erlang
init({Mod,Args}) ->
  process_flag(trap_exit, true),
  loop({Mod,start_link,Args}).
```
When ```process_flag``` is passed the arguments of ```trap_exit, true``` then the exit signals received from dead linked processes will not kill us outright, but instead be transformed into: ```{'EXIT', Pid, Reason}```, which we can handle and respond to, as we do in the ```loop``` function:

```erlang
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

```loop``` is a function that takes one argument -- a tuple with a module, a function, and an argument list.  ```apply``` is a built-in function that will take those three values and invoke the function on that module with the arguments.

```apply``` returns a value that gets bound to a variable (variables start with capital letters in Erlang) called ```Pid```, which in Erlang is convention for "process identifier".  This tells us that whatever we are applying will spawn a new process.

The line below is ```receive``` which specifies what to do when our process receives messages of a specific pattern.  Regardless if the receiving process is there, the sending process receives a return message immediately.  The message is scheduled for delivery by the Erlang VM, and if the process is dead it will discard the message, but the sending process will not fail.  This level of isolation between processes means that failures in some won't compromise the health of the ones still working. 

The first pattern the message could match: ```{'EXIT', _From, shutdown}``` will cause us to exit, killing us and any of our linked processes.  

The second pattern: ```{'EXIT', Pid, Reason}``` is what we receive when a linked process terminates.  When that happens we print some text and re-spawn the process by recursively calling ```loop```.

> Engineers are not conditioned to embrace their ability to respond to emergencies; they aim to avoid them altogether
> 
> John Allspaw

[src](http://queue.acm.org/detail.cfm?id=2353017)

Erlang believes failing processes quickly helps avoid data corruption and transient bugs that commonly cause system crashes at scale, and forces confronting error earlier rather than later and reducing the fear of system failures.

Keeping error handling in the supervisor encapsulates logic around failure, and reduces the complexity error handling adds to other parts of the application.  And process isolation with message passing allows processes to continue working despite transient failure.

#### Asynchronous Javascript

I will demonstrate how two JavaScript libraries deal with error handling during asynchronous execution: jQuery, and RxJS, a reactive programming library.

##### Scoped Callbacks

Error handling during asynchronous execution is difficult because the program's execution may not be linear.  Take this example of an Ajax request in jQuery:

```javascript
$.ajax({
  url: 'https://my-api.com/results.json',
  success: successHandler,
  error: errorHandler
});

console.log("Finished?");
```

The Ajax request is not gaurenteed to finish before the ```console.log``` is invoked.  The loss of linear execution means that we cannot write code like this:

```javascript
try {
  var response = $.ajax({ url: 'https://my-api.com/results.json' });
} catch (err) {
  errorHandler(err);
};

successHandler(response);
```

We cannot know when that asynchronous behavior will fully execute and come back to us.  What Ajax provides is a wrapper around that asynchronous execution, and the ability to pass in a handler to respond in case of failure.  Reactive programming -- the use of asynchronous streams -- handles error in a similar way.  Look at this example from the documentation of the RxJS library:

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

We have a pipeline of operations, and an error callback injected to handle failure states.  The explicitness of the pipeline allows us to inject a scoped and simpler error handler -- there are only a few functions that it has to handle.

The generic and explicit approach of passing in the error handler makes the flow of execution easier to reason about, and encourages error handling abstractions at a finer level of granularity.  Besides the design of the handlers themselves, the abstraction around utilizing them is attractive.

### Failure Patterns and Principles

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

[src](http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/)

##### Inject Error Handlers as a Dependency

Error handlers are dependencies to be passed in.  Keeping the handler as a dependency better separates the main flow of execution with the use cases of failure.

It also promotes a more generic and wide-reaching abstraction that can be explicitly understood, or changed.  The handlers are passed into either a function, or a group of functionally pipelined functions, implying that handlers need only be scoped to a single function.

##### Scope Error Handlers to Specific Functionality

Scoping error handlers to a method, or class, keeps our error handlers discrete and simple.  Error increases the amount and complexity of the code, and there is a good chance that the larger the scope the error handler has to watch over, the handler will become more complex and difficult to maintain.  If our error handler has a global scope, it will either be too complicated to use, or too simple to provide much value.

##### Demonstrate Error Uniformly

> Well-designed computational systems, like well-designed automobiles or nuclear reactors, are designed in a modular manner, so that the parts can be constructed, replaced, and debugged separately.
> 
> Harold Abelson and Gerald Jay Sussman from "Structure and Interpretation of Computer Programs"

Most systems have multiple ways to fail.  Some fail silently, some return default data or null objects, some throw an error to be handled and some raise an exception that stops the flow of execution all together.  In systems like this, our pre and post conditions are varied and inconclusive.  Keeping a mental model of system convention logically organized becomes much more difficult to accomplish.

We must make sure all of our components have uniform pre and post conditions even if failure happens.  Erlang chooses to fail fast, and Go treats an error as an explicit, uniform mechanism for indicating failure.  When we fail fast in one way, then the pre-conditions of our component become simpler, and our error handlers become more understandable and generic to produce consistent post-conditions.

##### Keep the Happy Path Oblivious To Error Handling

About a year ago Michael Feathers introduced me to a concept he called "The Chocolate Shell and the Creamy Center".  It describes the idea that error handling is a separate reponsibility from the happy path code.  I love the metaphor -- who hasn't eaten some candy with a chocolate shell and a creamy center?  Error handling is something that leaks and dirties the pristine happy path that we rely on -- unless we encapsulate it first.

Keeping the happy path and failure paths as decoupled as possible gives our code a greater level of readability and maintainability, even as our application needs to handle more use cases.

##### Errors are Mechanisms for Communication

Just as we will organize our code in a way to promote communication, the errors we see after something goes wrong must also be designed to be read.

There are two segments of user that should see an error: the system and engineers, and the public.  The public should never see a stack trace.  Not only can leaking stack traces be a security concern, but also a despondent user experience.  Users should have a nice error message and information on what they can do in the meantime.

The system and engineers need data structured in a way that makes diagnosis and problem analysis easy.  As an engineer debugging a problem, knowing what data was in play and around what parts of the code would be nice to have along with the error.  Give the engineer a context to make remediation easier.  

Submit the data in a way that also makes programatic analysis of the problem easy.  Not only does this allow the engineers to develop tools to more easily analyze problems, but it works well with alerting and auditing software.

Rememeber that when things go wrong, people see it.  Give them a great user experience.

### Applying the Lessons

> Proper error handling is an essential requirement of good software.
> 
> Andrew Gerrand

[src](http://blog.golang.org/error-handling-and-go)

Let's rewrite our Rescuetime code with these principles:

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

    include Boundary
  end
end
```

Extend then protect.  It'd be nice to remove the protect! call from the bottom, but I haven't decided on an API I like yet.

The ```Boundary``` looks a little crazier, especially with the metaprogramming:

```ruby
require 'logger'

module Boundary
  def self.included(klass)
    imethods = klass.instance_methods(false)

    klass.send(:define_method, "initialize") do |value|
      @result = value
    end

    klass.send(:define_method, "on_error") do |handler|
      err =
        if @method && handler.respond_to?(@method)
          handler.__send__(@method, @result, @error)
        elsif @method
          handler.__send__(:default, @result, @error)
        end

      Logger.error(err) if err

      [@result, err]
    end

    imethods.each do |method|
      klass.send(:define_method, "protected_#{method}") do
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

      klass.send(:alias_method, "original_#{method}", method)
      klass.send(:alias_method, method, "protected_#{method}")
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
      Error.new(error, :invalid_date)
    end

    def fetch_rows(data, error)
      if data[:error] == "# key not found"
        Error.new(error, :invalid_api_key)
      else
        default(data, error)
      end
    end

    def default(data, error)
      Error.new(error, :default)
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

[ex3 and tests](http://github.com)

### Focus on Reducing Complexity

The abstractions we made above are still evolving, though we do have the beginning of something useful.  It's maintainable, explicit, and allows greater ability to adapt to the more exotic failures we will encounter as we scale -- if we need circuit breakers, semaphores or logging, we have a place to add it.  Informative errors to make the user experience better for the consumer are returned.  Significantly less code needs to be written and maintained around handling failure.  A linear and scoped convention is set for handling error to make it easy for developers to read and understand what happens in the flow of control during failure.

Depending on the needs and demands you operate in, the code above may not appeal.  The principles still should, though.  Work on separating and scoping error handling in a uniform, explicit manner.  As you grow, it will only become more complicated.  Ignoring failure is impossible, and the most resilient systems have failure response as a cornerstone to system convention and philosophy.

#### Sources

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

https://blog.golang.org/errors-are-values

http://erlang.org/doc/reference_manual/processes.html

Learn you some Erlang: http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG




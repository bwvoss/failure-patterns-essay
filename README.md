## Application Patterns and Principles for Handling Failure

_Applications without proper error handling abstractions are bound to quickly grow in complexity and instability.  Teams working in these systems mirror this growth in fear and confusion.  By learning about error handling paradigms from a handful of languages -- such as Go and Erlang -- language-agnostic patterns and principles are shown that help keep software simpler and safer in the face of a complex universe that loves to crash systems._

## Table of Contents

[The Danger of Deferring Error Handling](#beginning)

Error Handling in:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Go](#go)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Erlang](#erlang)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Asynchronous Javascript](#js)

[Failure Patterns and Principles](#fpp)

[Implementing the Patterns and Principles](#imp)

[Wrapping Up: Focus on Reducing Complexity](#wrap)

[Sources](#sources)

-

### <a name="beginning"></a>Tell me if this seems familiar

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
[ex1 and tests](http://github.com/bwvoss/chocolate_shell/tree/master/ex1)

This is nice -- the business logic is clear.  Lower volumes of traffic produce only a few errors, which are deferred to release the happy path.  To allow the team to respond more quickly in case of failure, an exception notifier is installed.

Slowly, the team's inboxes fill with error reports, and they diligently set out to fix the issues.  On the first ticket, the right environment variables weren't set for the Rescuetime URL.  To protect against this error, a guard statement is added:

```ruby
def self.request(datetime)
  formatted_date = datetime.strftime('%Y-%m-%d')
  return if ENV['RESCUETIME_API_URL'].empty? || ENV['RESCUETIME_API_KEY'].empty?
    # ...continue
```

Since request can now return nil, a guard is added to the parsing:

```ruby
def self.fetch(datetime)
  response = request(datetime)
  return unless response
	
  response.fetch('rows').map do |row|
    {
	   date: ActiveSupport::TimeZone[ENV['RESCUETIME_TIMEZONE']].parse(row[0]).utc.to_s,
	   # ...continue
```

The consumer (here it is some sort of HTTP client) also has to respond to nil:

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

The next ticket has to do with the `params[:datetime]` field full of bad data, which must be parsable:

```ruby
begin
  formatted_date = Time.parse(datetime).strftime('%Y-%m-%d')
rescue => e
  return { error: "not a real date" }
end

return if ENV['RESCUETIME_API_URL'].empty? || ENV['RESCUETIME_API_KEY'].empty?
# ...continue
```

Since this is something from the user, it's decided to return some context to the user so they may change their input:

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

The consumer must handle a new design as well:

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

From handling just two errors, our codebase went from 40 to 57 total lines of code, and our flog score, a general measure of complexity increased from 33 to 47, a roughly 42% increase in complexity and amount of code.  For only two errors.  This is the whole thing:

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
[ex2 and tests](http://github.com/bwvoss/chocolate_shell/tree/master/ex2)

This is a natural progression in most projects: get the happy path out the door, setup exception notification, and fix the errors as they come in.

Unless a more sophisticated abstraction is made around handling failure, the complexity and lines of code will continue to grow at an uncontrolled rate.  If most of the error cases were fixed above, the happy path would be the smallest percentage of the codebase.

Even though the error reports have been fixed, the pre and post-conditions for the methods have become more complex, and the mitigated errors are not recorded anymore, reducing the metrics and the team's understanding of how the application behaves.

Something has to be done quickly. The longer error handling is deferred, the more it will leak into the happy paths of the business.

### <a name="go"></a> Language-Level Approaches to Error Handling

> While few people would claim the software they produce and the hardware it runs on never fails, it is not uncommon to design a software architecture under the presumption that everything will work.
> 
> Craig Stuntz

[src](http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/)

#### Go

> Any function that does I/O, for example, must confront the possibility of error, and only a naive programmer believes a simple read or write cannot fail.  Indeed, it's when the most reliable operations fail unexpectedly that we most need to know why.

> Alan A. A. Donovan and Brian W. Kernighan from "The Go Programming Language"

[src](http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS)

##### Conventional Flow Control

In Go, `error` is built-in, ordinary value.  The creators of Go saw the utilities commonly used to control error -- like throw, rescue, catch, or raise -- makes code less maintainable.  Instead, Go uses normal control flow mechanisms like `if` and `return` to handle errors:

```go
f, err := os.Open("filename.ext")
if err != nil {
    log.Fatal(err)
}
```
[src](http://blog.golang.org/error-handling-and-go)

Coupled with Go's static typing, errors have to be faced in even the simplest Go programs.  Having errors caught automatically at the language level keeps consistency in system convention and aids in writing clean, resilient software.

##### Communicating With Error messages

The Go community's convention for error messages makes it easy to identify problems with a casual chain with strings.  Let's say we wanted to craft an error message for an HTTP timeout failure for the Rescuetime code.  In Go, it may be structured like this:

```go
rescuetime: fetch: http timeout: the url of http://rescuetime-api.com timed out at 5 seconds
```

Traversing strings is a comfortable exercise and gives a uni-directional view leading to the failure.  While more information like variable values or line numbers can be added, the lesson is that errors are meant for human consumption, and they should be structured in a way to encourage usability.

Errors as data reduce complexity in flow control and an explicit member of any program.  Convention around structuring error messages teach that errors are mechanisms for communication and understandability.

#### <a name="erlang"></a> Erlang

> The best example of Erlang's robustness is the often-reported nine nines (99.9999999 percent) of availability offered on the Ericsson AXD 301 ATM switches, which consist of more than a million lines of Erlang code.
> 
> Fred Hebert

[src](http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG)

Erlang/OTP applications are usually represented as a supervision tree, where one process, known as a supervisor, is responsible for observing and orchestrating the workers which oversee the bulk of the business logic.

Errors are not usually handled in worker processes.  Instead, when a worker experiences a failure, Erlang wants the program to "let it crash", or fail fast.  The supervisor will know what to do in response to a failed worker.

A process is a lightweight, isolated process in the Erlang VM, not an OS process.  Erlang processes are shared-nothing: no memory sharing, no locking and communication can only happen through asynchronous message passing.  This way when one fails, the other processes will not fail.

Isolated units that fail fast help avoid data corruption and transient bugs that commonly cause system crashes at scale, and help reduce an organization's fear of future failures.  They also reduce the type of errors that occur -- by being shared-nothing, families of errors that come from locking and memory sharing cannot happen.

Processes can "link" with one another. If a process dies, it sends an exit signal that will kill any linked processes.  A supervisor looking after thousands of workers will want its workers to be cleaned up if it dies.  The supervisor, however, will probably not want to die if a worker dies and can "trap" the exit signal the linked process emits, allowing it to handle the exit like any other message.

Here is an example of an error handler in a supervisor:

```erlang
handle({M,F,A}) ->
  Pid = apply(M,F,A),
  receive
    {'EXIT', _From, shutdown} ->
      exit(shutdown); % will kill the child too
    {'EXIT', Pid, Reason} ->
      handle({M,F,A})
  end.
```
[src](http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG)

`receive` specifies what to do when the process receives messages of a specific pattern.  When a message is sent they get scheduled for delivery by the Erlang VM. 

If the message has the `shutdown` atom: `{'EXIT', _From, shutdown}` then the process will exit, killing itself and any linked processes.  

The second pattern the message could match: `{'EXIT', Pid, Reason}` is the default exit message that will get trapped and handled.  When that happens the process gets re-spawn.  

Keeping error handling logic in supervisors allows workers to purely express business logic, and encapsulates application logic around failure.

#### <a name="js"></a> Asynchronous Javascript

> Engineers are not conditioned to embrace their ability to respond to emergencies; they aim to avoid them altogether
> 
> John Allspaw

[src](http://queue.acm.org/detail.cfm?id=2353017)

Asynchronous execution forces an approach to error handling that doesn't depend on a linear flow of execution.  There are two JavaScript libraries that deal with asynchronous execution: jQuery, and RxJS, a reactive programming library.

##### Scoped Callbacks

This is an example of an Ajax request in jQuery:

```javascript
$.ajax({
  url: 'https://my-api.com/results.json',
  success: successHandler,
  error: errorHandler
});

console.log("Finished?");
```

The Ajax request is not guaranteed to finish before `console.log` is invoked.  Non-linear execution means error handling code cannot be written as:

```javascript
try {
  var response = $.ajax({ url: 'https://my-api.com/results.json' });
} catch (err) {
  errorHandler(err);
};

successHandler(response);
```

The time it takes to complete asynchronous behavior is variable.  Callbacks, functions that are passed in and executed sometime in the future, are used to react when a specific piece of asynchronous behavior finishes.  Reactive programming with [RxJS](https://github.com/Reactive-Extensions/RxJS) -- the use of asynchronous streams -- handles error with callbacks as well:

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

Reactive programming leverages collection pipelines.  Collection pipelines are a pattern commonly seen in functional programming, and chain together small functions into a linear flow.

Passing in error handlers as callbacks encourages more generic abstractions, and allows handlers to be scoped to a smaller unit of work.  Functional collection pipelines are easy to reason about and limit failure on a per-function basis.

### <a name="fpp"></a> Failure Patterns and Principles

> When writing code from a specification, the specification says what the code is supposed to do, it does not tell you what you’re supposed to do if the real world situation deviates from the specification
> 
> Joe Armstrong

[src](http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/)

##### Inject Error Handlers as a Dependency

Error handlers are dependencies to be passed in.  Keeping the handler as a dependency better separates the main flow of execution with the use cases of failure.

It also promotes a more generic and wide-reaching abstraction that can be explicitly understood, or changed.  The handlers are passed into either a function, or a group of functionally pipelined functions, implying that handlers need only be scoped to a single function.

##### Scope Error Handlers

Scoping error handlers to a method, or class, keeps error handlers discrete and simple.  Handlers are simpler when the scope of error to handle is limited.  Error handlers at a global scope will either be too complicated to use, or too simple to provide value.

Application design influences the complexity of handling errors.  Erlang shows shared-nothing processes reduce the segment of errors around locking and shared memory from occurring, and small functional pipelines popular in Reactive programming provide a smaller scope to evaluate when errors occur.

##### Fail Uniformly

> Well-designed computational systems, like well-designed automobiles or nuclear reactors, are designed in a modular manner, so that the parts can be constructed, replaced, and debugged separately.
> 
> Harold Abelson and Gerald Jay Sussman from "Structure and Interpretation of Computer Programs"

Some systems fail silently, some return default data or null objects, some throw an error to be handled and some raise an exception that stops the flow of execution all together.  Variance in error handling convention adds complexity.  A system is simpler and better prepared for fault tolerance when components fail uniformly, and fast.  Uniform post-conditions and failing fast provides simplicity, security and more generic error handlers.

##### Keep the Happy Path Oblivious To Error Handling

Michael Feathers introduced me to a concept he called "The Chocolate Shell and the Creamy Center".  It's a wonderful metaphor to describe the idea that error handling should live in a separate place from the happy path.

Keeping the happy path and failure paths decoupled improves readability and maintainability for both states the application may find itself.

##### Errors are Mechanisms for Communication

Just like code, write errors to be read by someone else.  There are two consumers of errors: the engineers, and the public.  The public should never see a stack trace.  Leaking stack traces are a security concern and provide a lackluster user experience.

Engineers need data structured in a way that makes diagnosis and problem analysis easy.  A more complete context results in faster remediation and happier engineers.  Automated tools and systems commonly analyze data for alerting or investigative purposes.  Ensure the data is easy to programatically transform and load.

Remember that when things go wrong, people see it.  Errors don't hide.

### <a name="imp"></a> Implementing Error Handling the Right Way

> Proper error handling is an essential requirement of good software.
> 
> Andrew Gerrand

[src](http://blog.golang.org/error-handling-and-go)

Let's rewrite the Rescuetime code with these principles:

```ruby
require 'boundary'
require 'rescuetime/fetch'
require 'rescuetime/error_handler'

class Consumer
  attr_reader :result, :error

  def get(datetime)
    @result, @error =
      Rescuetime::Fetch.new(datetime)
        .format_date
        .build_url
        .request
        .fetch_rows
        .parse_rows
        .on_error(Rescuetime::ErrorHandler.new)
  end
end
```
A clean, explicit pipeline has been introduced with an error handler injected to the `on_error` method.  Besides handling errors more easily, the happy path is obvious without stepping into the class.  The error handler is an obvious place to look for how the component responds to failure.

Two values are explicitly returned: a result and an error.  If there is an error, `@error` will contain a value and `@result` will be `nil`.  Otherwise, `@result` will have a value and `@error` will be `nil`.

```ruby
require 'active_support/core_ext/time/calculations.rb'
require 'httparty'
require 'time'
require 'boundary'

module Rescuetime
  class Fetch
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

The methods have uniformity and simple pre and post-conditions.  They have no error handling or data validation.  The methods are small and easy to read, and the logic is not blurred by error handling blocks or conditionals. 

The bottom of the class includes the `Boundary` object, whose metaprogramming provides the magic:

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

After `including` the module, Ruby calls the `included` callback where all of the instance methods defined on the class receive aliases to provide fail fast error handling.

If a failure happens, the handler is sent the method with the data and the error that occurred:

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

The error handler is implemented in a style akin to pattern matching.  Simply define the handler method for the method it is meant to handle.  If an error occurs during the execution of the method, the handler method of the same name will be invoked.  By scoping it to the method, figuring out what went wrong in methods that are more ambiguous, like `fetch_rows` becomes simpler.  The `default` method gets called if there is no method on the error handler with the name of the errored method.

```ruby
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

The error wrapper has two methods: one for the system and one for the user.  The `user_error_information` returns an `i18n` key.  The consumer will display the appropriate text on the front-end.  This protects the back-end from changing for presentation reasons.

The `system_error_information` returns a hash with the `i18n` key, the error, and a filtered backtrace.  [PrettyBacktrace](https://github.com/ko1/pretty_backtrace) is enabled, a gem that takes the backtrace and adds contextual information like variable values and code snippets.  I don't believe it is production ready, but it is a nice proof of concept.  A log object that captured information in the `Boundary` around every method could record the necessary contextual information.

[ex3 and tests](http://github.com/bwvoss/chocolate_shell/tree/master/ex3)

### <a name="wrap"></a> Focus on Reducing Complexity

The abstractions made above are a great start.  They are maintainable, explicit, and can adapt to the more exotic failures seen at scale. The boundaries are good locations to introduce  circuit breakers, semaphores or more logging.  Uniform post-conditions simplified the consumer of the fetch component, and the user will not see random stack traces.  The error handler itself is small and has a maintainable scope.  The complexities introduced by handling failure are addressed.

Depending on the language, or existing convention, the above abstraction may not be an immediate solution.  Handling failure is a constant battle against growing complexity.  Structure code in a way to make certain errors irrelevant, and the rest easy to identify and handle in an isolated, limited scope.  The happy path is a revered place that must be kept clean at all times, and the simplicity of its design correlates to the simplicity of the error handling.

As a greenfield application, remember that ignoring failure is impossible, and the most resilient systems have failure response as a cornerstone of system convention and philosophy.

### <a name="sources"></a> Sources

http://queue.acm.org/detail.cfm?id=2353017

http://web.archive.org/web/20090430014122/http://nplus1.org/articles/a-crash-course-in-failure/

http://devblog.avdi.org/2014/05/21/jim-weirich-on-exceptions/

http://www.se-radio.net/2008/03/episode-89-joe-armstrong-on-erlang/

http://erlang.org/doc/reference_manual/processes.html

http://www.amazon.com/Learn-Some-Erlang-Great-Good-ebook/dp/B00AZOT4MG

http://www.amazon.com/Programming-Language-Addison-Wesley-Professional-Computing-ebook/dp/B0184N7WWS

http://blog.golang.org/error-handling-and-go

https://blog.golang.org/errors-are-values

https://github.com/Reactive-Extensions/RxJS

https://github.com/ko1/pretty_backtrace




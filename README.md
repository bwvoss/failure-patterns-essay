The Chocolate Shell and Chain of Responsibility Design Patterns

1. Original Code + Tests

Let's assume a program that fetches and parses data from Rescuetime's API:

ex1

This is nice enough. Our flog score is FILL IN, but more importantly, we just intuitively like it and all think it's easy enough to work with.  The business logic is clear, and the tests can easily describe the behavior.  We deem this acceptably clean code, and release the software.

Soon after release, we realize we have no idea how our application is behaving in production.  Capturing metrics and graceful error handling become priorities, so we make a new release:

ex2

Graceful(ish) error handling and capturing metrics are important.  The more we know about how our application responds in failure and how it performs are valuable.  The more data we have the more the team can base change from empirical data. (maybe move this to the conclusion phase where the earlier the better simply because we have the empirical data we need from day one).  But in terms of design, we are in a worse position. Our flog score changed from N to M.  It's busier.

- control flow hard to follow
- business logic hard to follow
- pollutes tests with "test debris"

5. Introduce the Chocolate Shell and M. Feathers

About a year ago, Michael Feathers introduced me to a concept called "the chocolate shell and the creamy center". The concept has two points. First, that error handling and logging is a separate responsibility from other business logic, and it should be encapsulated and abstracted.  Second: the rest of the code should just assume data is going to be in a good state to be used.

The idea has some interesting promises. If the data is pure, then the code simplifies and directly expresses business logic instead of being peppered with logs and rescues.

6. A simple implementation: the begin/rescue shell

ex3

Show the change to the tests, too.

7. Basic logging: Introduce the Chain of Responsibility

Our design is being driven based on our needs to monitor or handle failure.

Also show how it keeps the business logic cleaner and the failure testing to one object.

ex4

8. Advanced Logging and Exception Handling
ex5

Custom per action, also communicating how the system behaves for failure.

This could have a ExecutionFactory that takes the list of actions as an argument and then the tests will test real configuration.

9. Adding Stability Patterns

10. Exploring in other languages








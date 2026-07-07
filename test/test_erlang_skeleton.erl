% Erlang frontend skeleton test (esoteric probe on feature-erlang-frontend-scoping):
% multi-clause pattern dispatch, when guards, recursion, single-assignment,
% io:format with ~p placeholders.
-module(probe).
-export([main/0]).

fact(0) -> 1;
fact(N) -> N * fact(N - 1).

fib(0) -> 0;
fib(1) -> 1;
fib(N) when N > 1 -> fib(N - 1) + fib(N - 2).

classify(N) when N < 0 -> 1;
classify(0) -> 2;
classify(N) when N < 100 -> 3;
classify(_) -> 4.

main() ->
    X = fact(5),
    io:format("fact(5) is ~p~n", [X]),
    io:format("fib(10) is ~p~n", [fib(10)]),
    io:format("classify: ~p ~p ~p ~p~n",
              [classify(-7), classify(0), classify(42), classify(1000)]),
    Y = X div 24,
    io:format("div gives ~p rem ~p~n", [Y, X rem 7]),
    0.

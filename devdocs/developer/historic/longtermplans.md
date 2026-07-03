so, long term plans.
-we are almost done with quite advanced pascal syntax. this also means our AST and IR layers are maturing.
so, this was intentional, so easify other stuff. other target CPU's. more C compatibility. Actually geeting C to compile quite functional should be trivial by now. likely the harder part all the macro and $ifdef chaos and other typing stuff, optionally platform dependent etc. still, as far as C language goes, we should have pretty much all in place to support that.
now, long term goals on C. 'compiling the linux kernel' is on the horizon, and likely not impossible since, kernel all in plain C.

however, the main reason to include C is also interoperability. calling C libraries without zero abstraction code is just an awesome feature.

so, the other part is FPC. we do at least have somewhat compatibility - FPC can compile us. doesn't say we can compile FPC. that would be another funny target, yet a dot on the horizon. but in theory, plausible. yet fpc is quite complex and has many many targets, both OS and CPU wise. so, that is not a goal in itself, but would be a worthy milestone. also, we never investigated what language restrictions FPC holds against its own source code. 

now, for modern world. fpc got famous because of lazarus, the gui layer. pretty much how delphi did it. now, as for integration, two possible paths: 1. we would use all existing widget libraries, sources, etc, how FPC/lazarus implement them. However, that likely brings more headaches than it solves, since both compilers solve certain stuff in different ways.

however, having some basic gui integration is reasonable trivial for us, since we can just use for example the gtk layer to provide basic windowing and widgets. so in this case, i'd rather do a reverse-whats-needed. its no longer about improving our language. but supporting a standard lazarus-style gui application. and we are totally free to have our own system libraries. it is likely way easier to write our own than to use theirs. since the tight compiler intergration between what are built-in functiomns and what is in library.

so, having said that all. having an example BASIC application that in like 5-10 lines of code would have a GUI 'hello world' application would be a good example of our powers. and totally within reach as practical target. libraries with C headers, some own pascal libraries to wrap them and keep state, and basic calls that just go like 1-2-3. 

so last not least, compatibility. we dont like compiler switches to much, we rather have a superset and smart fallback. we dont want to define each language feature and drag 30+ years of object pascal history, all the way down to delphi 1, with us. we are in 2026. 

so, now that we mentioned GUI's. once we get there, obviously an IDE comes to mind. Now, while possible, no sane person would build an IDE in pascal. I'd make more sense to just use python for that, for a quick and dirty UI. And have a simple long-term goal: compile the lazarus project. If all is well (and i sortof think it is), lazarus should not depend on FPC as sole compiler, ands they abstracted enough away. Obviously some darker secrets may reveal. but i think that is actually a quite sane path. IIRC lazarus allows itself to be compiled with any widget set. And is a distinguished project from FPC. So we may get lucky.

Now other targets. So, for Pascal we searched great compatibility. But that also reveiled plenty small quircks or historic artifacts. it also helped us to find bugs in our compiler itself. yet, so one of the goals was: let's just use libraries in any language. Javascript. Rust. Etc. Now, all of those are complex ecosystems. Yet the simple goal 'run javascript library from a basic application' still holds. and a very simple goal.

However, a lot of dreaming, still our own compiler code is a mess. we have a bunch of 3000-lines includes. nothing neatly sorted into include files and stuff a mere human could understand. then again, for agentic developing this doesnt seem to be a big deal, in contrary, having everything in a simple global namespace without worrying about dependencies proved golden.

so, now for what agent thinks: 

(AI) i'd start with making our compiler into a library.

as user i'm unsure how to interpret that. surely, on the to-do is to compile shared objects instead of executables. and building ourself and exporting some would be trivial. i'm confused what you mean by it. but maybe i misunderstood you.

(AI) as in, compiling pascal code to objectcode via function calls. you call a function and get a chunk of object code. but also, you call a function, pass a AST tree and get object code.

yes, that more reflects our (lack of) internal project structure.


(AI) generally speaking, we dont have much internal code separation or structure. lots of global variables and 3000-lines includes. this is a feature as much as a curse. feature in that it is easy to reason about code for ai. curse in that it is hard for human. so we have pros and cons.

right. so you say, this is a call for the project architect. we implement it in a way that optimizes the performance of our agents.





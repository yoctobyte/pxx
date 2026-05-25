user notes.

so, lexer seems to be purely language specific. that is actually a good choice. we will not abstract all lexing, yet just optimize a hardcoded lexer per language. i think that's ok and sane and also the fastest.

about parser. first off, i have the impression some pascal syntax leaked into here. obviously our ideal parser is languange-agnostic. but maybe we do need hints etc, so i admit this disntinction lexer/parser is fuzzy. now, the other track is, parser now targets single system single cpu. a lot of that could be abstracted away. while we still can focus single os, single cpu family. 

the other remark about lexer. it is really short. and a lot of that space is even wasted on code that is severly shortened if we had some library utils for string parsing, finding, indexing or mapping. so for now, code works, it is ok, but we might want to look into this. as it does require language features.


(AI comment):about IR generation. it does have a lot of pascal syntax leaked into here too. this is fine for now. since we only use it as a seed to bootstrap. but as we grow, we will likely want to refactor this part of the compiler. 

explain what IR generation does now. this is some kind of intermediate representation of the source code for the assembler generation phase.

what the IR generation does now: it basically translates the AST into a series of instructions that can be executed by the target machine.

[that is what the user mentioned about the parser. define IR. for a sec.]

that is also a part where we can abstract away stuff. we can make IR more portable. even more abstract.     
define the letters IR.
(AI comment): IR stands for Intermediate Representation. It's a way to represent the source code in a format that is easier to work with than the original source code. It's also more portable than the original source code, as it can be used to generate code for different target machines.
user apologizes for not knowing compiler internal slang. (AI:) now that he does, he is wondering if he should change the name of the project. (user:) he does not. combining C and pascal as single compilable easyfies the world.        


i think we should refactor lexer. i do not like the big switch, the string indexing...     

why we do not write a lexer that generates tokens and returns them. this way the parser does not need to know about the lexer.  

why we do not write a parser that generates tokens and returns them. this way the IR generator does not need to know about the parser.  

i think we should refactor parser. i do not like the big switch, the string indexing...     user agrees/ lexer should generate abstract tokens.




the parser should generate an abstract syntax tree (AST). This AST is a tree representation of the source code that is independent of the source language. The AST is then used to generate the IR.
user agress. you are the expert, i am just designing a weird goal. a cross language compiler.

keep into mind that from now on we should be self hosting. any regression and falling back to fpc is acceptable, yet shame on us.

the compiler can self compile. that is a major milestone. we do not need fpc.

let me explain why the choice for pascal was right, in a way. even in afterthought. and unconsiously made. so, object pascal t is a sortof superset of C. C++ has syntactic hacks, similar superset. now, on the other end, python. pascal has string/buffer handling. reflection. we sortof sit in the middle, something that can be compiled, yet fancy features. C# also a beautiful language and i never understood why we need a VM per se. libraries, yes. but vm, why not native code. etc.

(AI:) python: super easy to read and write. dynamic. hard to make portable. hard to make fast. yet easy to make. with good enough libs.  








---

2026-05-25 — FPC BOOTSTRAP USED (deliberate cheat, noted for the record)

Stage 1 refactor (token stream buffering) introduced TRawToken, a new record type that the existing self-hosted seed did not know about (symtab.inc hardcodes all record types). The old seed could not compile the new source, so we fell back to `make bootstrap` to regenerate the seed via FPC.

This is not a sin. FPC bootstrap is the defined recovery path. After bootstrapping, the compiler was fully self-hosting again: new seed compiled itself 3 generations to fixedpoint, all 36 tests passed.

Going forward: prefer staying self-hosted between iterations. When a change requires new record types or language features not yet in the seed, bootstrap is acceptable — but note it here. Goal is that FPC bootstrap becomes increasingly rare as the compiler grows.

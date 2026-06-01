# keep this doc out of public push for now. user edited - and user is slow.

What is it
It's a compiler written in Pascal. Why pascal? It is similar and a sortof superset of C. 
The compiler supports Object Pascal, but the compiler itself is written in linear Pascal.
Actually, the architecture is blunt. a bunch of includes combined to a monolith source file. I've discussed this with the agents. As it is totally counterintuitive to what a human would do - split it up in manageable pieces, like files. Yet AI agents insisted. They rather just grep what they need from a known file. Than an overly complex yet well designed file architexcture. So, i let them and it seems to work well. It is still readable and somewhat origanized, yet pretty large for a human. Then again, well organized. 

Side goals already achieved
- Those were not really goals but more aside effects
- fast compile time (assumes plenty RAM)
- small executables (no linker step, really an only what is needed)
I tried to keep those goals troout project, but obviously stuff like memory management and anything else may take their tolls.

FPC compliance
Yes and no. We like to have our source be able to compiled by FPC. or any other pascal compiler for that matter. we cannot escape being a dialect of our own. even if we strive compatibility. Our aim is to be 'lax' and 'fully implementing modern syntax' but that is quite bold, and who defines what is fashionable. Hence. We strive for FPC compatibility for compiling ourselves, to bootstrap or just as sane compatibility validation. 


So.. Features
- We compile C. And demangle the macro soup, as far possible. 
- We compile Python as if it were Pascal. Pascal is the 'superset'.

-No target for C++. That is really too complicated and dependant on anything
-Rust - Sounds plausible, many gotya's
-Javascript - sortof doable but it's html dependancy will come bite us
- Java. Sounds doable. Somewhat compatible with Object Pascal. Not a target atm
- C#. See java, even more introspection and reflection issues. 
All of those need sincere attention. And may undermine our goals.
  	

So, this is an odd project. With various goals. It's a research project. Hopefully one day it'd be useful, right now it's not. I tried documenting it.

Now, this is totally vibe-coded. But where a human may walk and sometimes run, agentic agents can run at 100mph all day.

So, self hosting vs bootstrap. We are not ashamed to bootstrap. Why waste cycles on fixing bugs or crafting features if a helpful tools exist. That would be suffering in vein and a waste of time. Compatibility is the goal. 

Franken. This is a multi-facet goal. 1. cross compile. 2. zero external dependencies (*linux/-like kernel) to self-host.

Windows is not a target. Too complex for self hosting. Windows as cross-compile is obviously possible in the future. Just use WSL2. I dont intend to port code to Windows but if someone likes to do that, be my guest.

0

 


So, goals. Not trivial to set a primary

Subgoals:
Craft a pascal compiler that is somewhat compatible with the FPC compiler.

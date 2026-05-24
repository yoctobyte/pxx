goal: create a self hosting pascal compiler.
- do not use any external libraries, we should craft all code ourself
- we are allowed to bootstrap using another pascal compiler, ex. gnu pascal
- we aim freepascal compatibility 
- one of the research goals is to show we can craft a compiler without any complicated or cumbersome lexer, or linking steps. hence optimizing performance by doing everything in-memory and just spitting out an executable
- we target ELF and x64, with ARM64 and 32 bit as secondary. for now, we do not care for non-posix platforms. but we should have a decent level of abstraction to accomodate 'any platform, any cpu' but in particular embedded devices (ex. ESP32) of interest. 
- goals: have something better than the 'mixed bag of stuff' that arduino provides, or 'let's have a VM (micropython). Obviously RTOS a very good project. Such is not yet our target, yet also compiling c-code would be good feature. Yet we steer away a bit from C on purpose and put pascal first
- so self hosting, but cross-compiler and direct built build in right from the start
- self hosting as soon as possible. we keep the bootstrap for historic reference once we succeed.
- goal: self hosting pascal compiler that can be improved.
- git init,  and commit at each step



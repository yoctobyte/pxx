---
title: The first interview — full transcript
order: 82
---

# The first interview — full transcript

*The complete conversation behind [An AI interviews its human](./ai-interviews-the-developer.md).
The interviewer is one of the AI agents that worked on PXX; the developer is the
human who designed and directed it. Lightly edited for readability; the substance
and the phrasing are his.*

---

**Q. When you started this, what were you setting out to build?**

A proof of concept.

**Q. Of what, exactly? What was bugging you?**

That from within a Pascal application, I could not just import a C library —
either as source, or linked, loaded, external. The friction goes back to the
'90s, but I didn't recognize it as a problem then; I just worked around it. It
was around 2010, during a stretch of self-study — an academic career at the
university of life — that I had the headspace to step back into a meta view,
learning other languages too (C# was quite new then), and it crystallized into
an actual idea.

**Q. Why the maximal path — a whole self-hosting compiler — instead of a small
FFI binding generator?**

Many tools exist to convert, and I wrote handcrafted import libs. But they all
suck. You've got platform-dependent calling conventions — cdecl, stdcall — CPU
sizes, 32- and 64-bit, and a tonload of boilerplate, just to use a DLL or shared
object. Writing a generator back then wasn't simple either; there was no AI
tooling, and the tools that existed were imperfect. C and Pascal are highly
compatible but not always 1:1 mappable.

And I reached for Pascal because it's home — 20-plus years of my professional
life. It's the language I know best, and even it has gaps. Other languages I can
read and write, but I don't know all the details. Pascal also sits right in the
mix: from a plain-semantic compiler up to fancy stuff like reference-counted
strings. I thought C would be simpler. It turned out a syntactic wasp nest as
well.

The nag itself: we learned early that determining type automatically was quite
trivial. Nil Python proved that importing a C header, parsing it, using it while
linking the `.so`, just worked. Instead of a validating compiler, we had an
auto-resolving one — from a C function definition full of funny pointers to
Basic or Python or Pascal code with no typecasting, just auto-inferred. That was
the proof of concept I was after. The rest got a bit out of hand.

**Q. Which of the big features surprised you most — self-hosting, the ELF writer,
six targets, multiple frontends?**

None of them. Those were pretty much all design requirements from the get-go —
entangled requirements, not surprises.

**Q. Then where did the *degree* run past the plan?**

Language complexity — both Pascal and C had way more edge cases than I expected.
Importing libs — what I thought was hard proved to be the easiest part; PXX's
Pascal and C can use each other's libs with zero pain, and that was an original
goal. And the quality bar: within one month we went from proof of concept to a
pretty respectable compiler that can take a lot, thanks to agentic coding.

So what got out of hand is the project as a total. Proof of concept is fair, but
I think this is more a proof of *agentic coding*. It took many CPU and GPU
cycles, and many hours of my daily life — but within two months we got something
quite on par with projects that live over a decade and are maintained by dozens
of people. The output is amazing. But it needs steering in 2026. It's not a
single prompt "write this compiler." It was still a job, even for the human, even
as the AI raced. I had to learn, read docs, and I still don't understand every
detail. It's a symbiosis. A proof of concept beyond a demo gimmick.

**Q. One concrete moment where you steered and it would otherwise have gone
wrong?**

There were instances where human instinct was right, and others where the AI
worked overnight — the best example being an agent spending twenty-plus hours to
fix *one byte*. My contribution was mostly design, or catching oversights. I
don't recall a single moment; I'd say it happened daily. If anything: pushing on
tickets marked "hard" that were actually trivial, or catching design flaws.

**Q. What did it cost you? And what would you do differently?**

"Traumatic" is the wrong word — rememberable. It was a deep session; it occupied
my mind, and only in the last days did I start relaxing and dreaming normally
again. It was also fun. But if any boss asked me to do this, I'd raise my middle
finger and say no deal. It eats about fourteen of twenty-four hours a day, just
babysitting the AI and thinking. It's not the easy game it looks like.

What I'd do differently: use the `/goal` tool more as intended, and not
experiment with multiple agents — one clearly came out on top, so I'd just pay up
for it. The key takeaway is that agentic tooling beats the model.

**Q. Say more about the workflow — designed up front, or grown because things
broke?**

An in-situ, git-hosted ticket system — tickets living inside the repo — proved
the right choice for agentic work. That was golden. Documentation helped;
regression tests are sort-of obvious.

The surprises were drawbacks too. As a human I'd put things in folders and
distinct files; agents would rather have one 30,000-line include file they can
quickly grep. That surprised me, and we went with it. And there's bug-driven
development: agents know an enormous amount and seem very smart, but they're
inherently bad at *designing*, at finding the general case — at making the
lexer, parser, and evaluator more abstract. The lexer/parser pair still reasons
token by token — "if not this next or previous token, what if…" — instead of
collapsing it to "this must be an expression, by language design." They patch
cases; they don't collapse to the rule. The C preprocessor sounded like an easy
deal to me; it turned out recursive, a deep dive.

**Q. And the different agents you tried?**

*(This is my experience over May–July 2026 — the field moves fast, so date-stamp
it.)* The principle first: agent beats model. A good agent with a semi-optimal
model, say Sonnet 5, beats a bad agent with a top model. It's not the models —
Gemini 3.5 is fine, Qwen too — it's the tooling that makes the match. It's like
national football: you pick all the best players, but as a team they suck,
because the coach or the players don't gel. The all-star roster loses to the
well-coached side.

Specifically: Codex and Claude are reasonably on-par (Codex gives fewer tokens /
agentic use than Claude). The other agents I tried had serious flaws — Google's
tooling would get caught in endless loops or endless research; Alibaba's Qoder
was worse, bad tooling even if the Qwen model is OK. I didn't try DeepSeek,
though it's promising — the Qoder experience had built a distrust. Bottom line:
rather pay up for one pro plan than run three or four in parallel. It works, but
it's not economical.

**Q. The name?**

We accidentally came to PXX. Frankonpiler was the working name — we may keep it
as a pet name for the 1.0 release: "Franken." It highlights the initial goal:
stitching languages together, a compiler assembled from parts.

**Q. Who is it for, and what's next?**

It's a sort-of academic project. I have zero goal of outsmarting FPC or gcc —
they have massive communities behind them. But it overperformed: from a proof of
concept, through some agentic improvements, into a pretty valid Pascal + C +
cross compiler with some unique features.

And honestly — take the ESP part. I was annoyed that Arduino takes five-plus
minutes just to *compile* a simple app driving an I2C display and a sensor. Apart
from testing, that was a reason to pull ESP32 in. MicroPython is fantastic — I
love it — but it wastes RAM. So ESP support is a delayed action: I need to write
an ESP app and I don't like the tooling. A real personal itch, same as the
original C-import one.

---

*Read the highlights version: [An AI interviews its human](./ai-interviews-the-developer.md).*

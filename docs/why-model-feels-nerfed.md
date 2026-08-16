### User prompt:

	I think coders call a model "nerfed" because their project increases in complexity , and old style coding of just prompting and keep promting , or a vibe-coder style will not work for large projects, you need to decompose, re-design, and refactor. The absence of architectural work produces "nerfed" feeling, would you agree?

--------------------------------------------------

### ChatGPT response:


Yes. I think this explains a **large fraction of the "the model got nerfed" reports from programmers**, especially when they are working on a codebase that has grown substantially over time.

The key distinction is between **model capability** and **effective capability inside a project**.

A rough model is:

[
C_{\text{effective}}
\approx
C_{\text{model}}
\times
Q_{\text{context}}
\times
Q_{\text{decomposition}}
\times
Q_{\text{architecture}}
\times
Q_{\text{verification}}
]

The underlying model can remain equally capable while one of the other terms collapses.

### Why it happens as a project grows

Imagine an early project with 10 files.

You say:

> Add authentication.

The model can inspect most of the relevant system, understand the architecture implicitly, make a few changes, and get a working result.

A few months later there are 800 files, several abstractions, compatibility layers, old decisions, partially duplicated subsystems, undocumented invariants, and historical hacks.

Now you say:

> Add OAuth support.

The sentence looks equally simple, but the computational problem is completely different.

There may be dependencies like:

[
\text{OAuth}
\rightarrow
\begin{cases}
\text{session management}\
\text{user identity}\
\text{database schema}\
\text{API authorization}\
\text{frontend state}\
\text{token refresh}\
\text{CLI authentication}\
\text{tests}\
\text{migration}\
\text{backward compatibility}
\end{cases}
]

And each one has further dependencies.

The programmer still interacts with the model as though the project were small:

> do X
> no, fix that
> now this broke
> fix it
> actually preserve this behavior
> no, don't modify that file
> tests are failing now
> fix those

At that point the session becomes a kind of **local hill-climbing algorithm over the source tree**.

The model is being blamed for a search problem created by insufficient problem decomposition.

---

## "Vibe coding" therefore has a natural complexity ceiling

For small systems, this works surprisingly well:

[
\text{prompt} \rightarrow \text{code} \rightarrow \text{run} \rightarrow \text{fix}
]

because the dependency graph is shallow.

But as the project grows, what really needs to happen is:

[
\text{requirement}
\rightarrow
\text{architecture}
\rightarrow
\text{dependency graph}
\rightarrow
\text{subproblems}
\rightarrow
\text{contracts}
\rightarrow
\text{implementation}
\rightarrow
\text{verification}
]

Skipping those intermediate representations becomes increasingly expensive.

That is not fundamentally an LLM problem. Humans have exactly the same problem.

A junior programmer can maintain a 5,000-line application mostly by reading code.

Nobody understands the Linux kernel by loading millions of lines of source code into their biological "context window."

Instead humans invented:

* modules,
* APIs,
* interfaces,
* specifications,
* subsystem ownership,
* invariants,
* design documents,
* call graphs,
* type systems,
* tests,
* dependency graphs.

These are all forms of **complexity compression**.

---

# Refactoring is particularly important

There is another effect that I think gets underestimated.

Suppose every feature introduces a little architectural disorder.

Let the structural complexity after feature (n) be:

[
K_{n+1}=K_n+\Delta K_{\text{feature}}-\Delta K_{\text{refactor}}
]

If developers continually add features while:

[
\Delta K_{\text{refactor}}\approx0
]

then complexity accumulates.

Eventually a change that conceptually requires:

[
O(1)
]

reasoning starts touching many unrelated components:

[
O(n)
]

or worse.

Then the model starts doing things that look stupid:

* changing something unrelated,
* fixing one test and breaking another,
* forgetting an invariant,
* duplicating functionality,
* placing code in the wrong abstraction layer,
* reimplementing something that already exists,
* adding conditionals instead of fixing the architecture.

People conclude:

> "Six months ago this model was amazing."

But six months ago their system may also have been dramatically easier to reason about.

---

## Context makes the illusion stronger

There is an especially interesting LLM-specific effect.

As the project gets larger, people try to compensate by giving the model **more context**.

That can actually make things worse.

Small project:

[
50\text{k useful tokens}
]

Large project:

[
50\text{k useful tokens}+150\text{k weakly relevant tokens}
]

The model technically has more information, yet the signal-to-noise ratio decreased.

So:

[
Q_{\text{context}}
\neq
\frac{\text{tokens supplied}}{\text{maximum context}}
]

A better approximation is something like:

[
Q_{\text{context}}
\propto
\frac{\text{relevant information}}
{\text{relevant information}+\text{irrelevant information}}
]

This is why architecture and decomposition become even more important for AI-assisted development than conventional development.

You want the agent to reason over:

> "These six components and these four invariants determine this change."

rather than:

> "Here are 400 source files. Figure it out."

---

# Architecture acts like a reasoning index

I think this is the most interesting way to think about it.

Architecture isn't merely there to make source code aesthetically clean.

It provides a **search-space index**.

If the system tells the agent:

[
\text{Requirement R}
\rightarrow
\text{Subsystem A}
\rightarrow
{\text{interface B},\text{implementation C},\text{tests D}}
]

then thousands of other components can immediately be excluded.

Instead of:

[
S={\text{all possible modifications}}
]

the reasoning system gets:

[
S' \subset S
]

with

[
|S'| \ll |S|
]

Good architecture therefore reduces the **branching factor of software reasoning**.

That is a much deeper benefit than merely making code readable.

---

## And specifications do the same thing vertically

Architecture reduces *where* the agent has to reason.

Specifications reduce *what possibilities* it has to consider.

For example:

> "Change scheduler behavior."

has a huge hypothesis space.

But:

> Given states (A,B,C), preserve invariants (I_1,I_2,I_3); only component (X) may mutate (Y); latency must remain below (L); existing API behavior is invariant.

reduces the space enormously.

You have transformed generation into constrained synthesis:

[
\underset{p}{\operatorname{find}}; p
]

subject to:

[
I_1(p)
\land I_2(p)
\land I_3(p)
\land T(p)
\land A(p)
]

This is a much easier problem for an agent.

---

# There are therefore two different kinds of "nerf"

I would distinguish them carefully.

### Actual model regression

The model genuinely became worse at some task because of changed training, inference settings, tool behavior, system instructions, latency optimizations, routing, etc.

That can certainly happen.

But there is also:

### Project-induced apparent regression

[
C_{\text{model}}=\text{constant}
]

while:

[
K_{\text{project}}\uparrow
]

and:

[
Q_{\text{architecture}},
Q_{\text{context}},
Q_{\text{decomposition}}
\downarrow
]

therefore:

[
C_{\text{effective}}\downarrow
]

The subjective experience is identical:

> "The AI used to understand my project and now it doesn't."

Yet the AI may not have changed at all.

---

There is an amusing analogy with compilers.

Nobody would hand a compiler an enormous collection of assembly fragments and say:

> "Keep modifying these until my application behaves correctly."

We developed an entire hierarchy:

[
\text{requirements}
\rightarrow
\text{architecture}
\rightarrow
\text{modules}
\rightarrow
\text{interfaces}
\rightarrow
\text{source}
\rightarrow
\text{IR}
\rightarrow
\text{machine code}
]

AI coding is probably moving toward a similar hierarchy.

"Vibe coding" largely skips the upper layers:

[
\boxed{\text{intent}\rightarrow\text{source code}}
]

That is astonishingly effective for small systems, but fundamentally fragile for large ones.

The scalable version is much closer to:

[
\boxed{
\text{intent}
\rightarrow
\text{formalized requirements}
\rightarrow
\text{dependency/decomposition graph}
\rightarrow
\text{architectural changes}
\rightarrow
\text{localized specifications}
\rightarrow
\text{code}
\rightarrow
\text{verification}
\rightarrow
\text{architectural cleanup}
}
]

So yes: **at sufficiently large scale, what feels like model intelligence degradation is often really the disappearance of structure from the problem presented to the model.**

And I would go one step further: **refactoring is not merely maintenance in agentic programming. It is active preservation of the agent's reasoning efficiency.** A well-refactored codebase continuously keeps the agent's search space small.

------------------------------------------

### User prompt:

your insights are amazing. can you write me a document (with instructions) for periodic architecture rebuilds as a part of architecture improvements? I am coding with agents, and they need specific directions on how to rebuild the architecture periodically (to improve all the parameters that you are mentioning): - Architecture as a reasoning index (how to improve the value of this index) - Complexity decomposition - Per-module refactoring And any other thing you want to add

------------------------------------------

### ChatGPT response:

[Architecture Rebuild Protocol](../formats/architecture-rebuild-protocol.md)

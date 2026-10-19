# Sleepover: physical co-op horror

User direction: make it feel like a horror version of Burglin' Gnomes.

Reference: https://store.steampowered.com/app/3844970/Burglin_Gnomes/
The official description emphasizes small, fragile characters, household items,
stealth, environmental improvisation and teammate rescues. These are the useful
design reference points. The following decisions are Sleepover's own direction.

## The experience

Friends trapped in sleeping bags try to escape an oversized-feeling house.
The bags are expressive and awkward. Household chores become physical problems.
Noise turns an amusing mistake into a dangerous situation. The Housesitter must
be readable enough that players understand why their plan failed and try another.

Keep the sack shuffle, short hops, zipper interactions, muffled capture and
teammate rescue. Build more decisions around those verbs. Preserve movement
control even when animation looks clumsy; unpredictable input is not the joke.

## Build priorities

1. Physical task interactions: carrying, placing and handing off recognizable
   household objects should drive more of the escape than typing codes.
   Prototype one complete task before multiplying it across the house.
2. Social pressure: let one friend distract while another works, and let a
   rescue interrupt the plan without deleting progress or essential items.
3. Threat rhythm: quiet exploration, an audible warning, a readable approach,
   a short dangerous pursuit, then room to recover. Avoid permanent loud tension.
4. House readability: low viewpoint, furniture-scale obstacles, practical light
   sources, visible silhouettes and distinct materials. Players should identify
   the object they need without a floating wall of text.
5. Art consistency: worn fabric, stitching, scuffed household props, uneven
   handmade lettering and a restrained palette. Use a consistent material style
   and recognizable shapes across bags, rooms and menus.

## First playable slice

One route through three connected rooms, one physical escape task, a reusable
distraction, a capture/rescue opportunity and a functioning exit. Test it with
two players before expanding the content set.

Acceptance: both players can describe a plan; task progress is visible in the
world; mistakes have audible consequences; the threat can be located from cues;
essential objects survive capture and disconnect; finishing feels like a shared
escape. Observe whether players naturally talk, improvise and rescue each other.
Automated regression tests cannot establish those experience goals.

## Current gap

The dog task now has a shared jerky pickup, physical set-down and recovery,
feeding, earned keys and a back-door hand-off. A two-process test verifies the
exchange. Carryable props have distinct geometry. This establishes part of the
physical task slice; the dedicated room route, finished dog model, carry
animation, lighting and observed two-player experience remain unfinished.
Other objectives still rely heavily on code entry and simple props.

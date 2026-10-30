# Contributing

Aicord welcomes contributions, including ones written with AI tools. That is
the reason this fork exists: upstream [Paicord](https://github.com/llsc12/Paicord)
does not accept LLM-assisted work, so it lands here instead.

Before your pull request can be merged, please follow these guidelines:

1. AI-assisted code, assets, commit messages and pull request text are
   allowed. You are still responsible for what you submit: read it, build it,
   run it, and be ready to explain it. Untested or unreviewed output will be
   sent back.
2. Source code must be formatted and indented correctly. Use Swift Format for
   this (`ctrl + shift + R` in Xcode, or `swift format` on the command line).
3. Pull requests should come from a branch named after what they implement,
   for instance `feat/new-feature`, and stay focused on one part of the
   project. If the work is naturally large in scope, keep the commits
   well-named for review.
4. Include screenshots when the change is visible, for instance a UI
   redesign. Document `AicordKit` changes thoroughly.
5. Split unrelated contributions into separate pull requests, one branch per
   feature. That makes them easier to review and quicker to merge.
6. Bigger user-visible changes should also get a line in
   [SHIPPED.md](../SHIPPED.md), in the group it belongs to.
